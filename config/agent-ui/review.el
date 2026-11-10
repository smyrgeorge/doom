;;; $DOOMDIR/config/agent-ui/review.el -*- lexical-binding: t; -*-
;; Agent UI's review of the types the agent made (staging.el): a list of
;; them, a preview of each (what it is, its properties, its example drawn,
;; its code), keep or discard. Loaded from config/agent-ui.el. No Doom here.
;;
;; M-x agent-ui-review, or R in a canvas (whose header says when types wait).
;;   RET  its preview          a  keep it          x  discard it
;;   v    its code             g  the list again

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)

;; ====== VARIABLES ======

(defconst agent-ui-review-buffer "Agent UI: types to review"
  "The list of the types the agent made.")

(defvar-local agent-ui-review--type nil "In a preview: its type's name.")

;; ====== THE LIST ======

(defvar-keymap agent-ui-review-mode-map
  :doc "Keys of the list of types the agent made."
  "RET" #'agent-ui-review-preview
  "a" #'agent-ui-review-keep
  "x" #'agent-ui-review-discard
  "v" #'agent-ui-review-source)

(define-derived-mode agent-ui-review-mode tabulated-list-mode "Agent UI review"
  "The element types the agent made, waiting for you to keep or discard
them.

\\{agent-ui-review-mode-map}"
  (setq tabulated-list-format [("Type" 18 t) ("Made" 17 t) ("Loaded" 7 t) ("What it is" 0 nil)]
        tabulated-list-padding 1
        ;; The columns' names in the buffer: the header line says the keys.
        tabulated-list-use-header-line nil)
  (tabulated-list-init-header)
  (setq header-line-format
        (substitute-command-keys
         " \\<agent-ui-review-mode-map>\\[agent-ui-review-preview] preview   \\[agent-ui-review-keep] keep   \\[agent-ui-review-discard] discard   \\[agent-ui-review-source] code"))
  (add-hook 'tabulated-list-revert-hook #'agent-ui-review--entries nil t))

(defun agent-ui-review--doc (file)
  "The first line of the documentation of the type in FILE."
  (let* ((forms (ignore-errors
                  (agent-ui--read-forms (with-temp-buffer (insert-file-contents file) (buffer-string)))))
         (define (seq-find (lambda (f) (eq (car-safe f) 'agent-ui-define)) forms))
         (doc (nth 2 define)))
    (if (stringp doc) (car (split-string doc "\n")) "")))

(defun agent-ui-review--entries ()
  (setq tabulated-list-entries
        (mapcar (lambda (file)
                  (let ((name (intern (file-name-base file))))
                    (list name
                          (vector (symbol-name name)
                                  (format-time-string "%Y-%m-%d %H:%M"
                                                      (file-attribute-modification-time (file-attributes file)))
                                  (if (agent-ui-staged-p name) "yes" "no")
                                  (agent-ui-review--doc file)))))
                (agent-ui-staged-files))))

(defun agent-ui-review ()
  "List the element types the agent made, to keep or discard."
  (interactive)
  (let ((buffer (get-buffer-create agent-ui-review-buffer)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'agent-ui-review-mode)
        (agent-ui-review-mode))
      (agent-ui-review--entries)
      (tabulated-list-print t))
    (pop-to-buffer buffer)
    buffer))

(defun agent-ui-review--refresh ()
  "The list again, where it's open; the canvases' headers."
  (when-let* ((buffer (get-buffer agent-ui-review-buffer)))
    (with-current-buffer buffer
      (agent-ui-review--entries)
      (tabulated-list-print t)))
  (agent-ui-review--canvas-headers)
  (force-mode-line-update t))

(defun agent-ui-review--name ()
  "The type at point, in the list or a preview."
  (or agent-ui-review--type
      (tabulated-list-get-id)
      (user-error "No type here")))

;; ====== A PREVIEW ======

(defvar-keymap agent-ui-review-preview-mode-map
  :doc "Keys of a preview of a type the agent made."
  "a" #'agent-ui-review-keep
  "x" #'agent-ui-review-discard
  "v" #'agent-ui-review-source)

(define-derived-mode agent-ui-review-preview-mode special-mode "Agent UI type"
  "A type the agent made: what it is, its example drawn, its code.

\\{agent-ui-review-preview-mode-map}"
  (setq-local truncate-lines t)
  (setq header-line-format
        (substitute-command-keys
         " \\<agent-ui-review-preview-mode-map>\\[agent-ui-review-keep] keep   \\[agent-ui-review-discard] discard   \\[agent-ui-review-source] its code   \\[quit-window] close")))

(defun agent-ui-review--code (file)
  "FILE's code, highlighted as Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents file)
    (delay-mode-hooks (emacs-lisp-mode))
    (font-lock-ensure)
    (buffer-string)))

(defun agent-ui-review--heading (text)
  (propertize (concat text "\n") 'face 'agent-ui-title))

(defun agent-ui-review-preview (&optional name)
  "Preview the type NAME (at point): loaded if it isn't (after a restart),
what it is, its properties, its example drawn, its code."
  (interactive)
  (let* ((name (or name (agent-ui-review--name)))
         (file (agent-ui--staged-file name)))
    (unless (agent-ui-staged-p name)
      (agent-ui-stage-file file))
    (let* ((type (agent-ui-type name))
           (buffer (get-buffer-create (format "Agent UI type: %s" name)))
           (window (display-buffer buffer '(nil (inhibit-same-window . t))))
           (ctx (agent-ui-context :width (max 20 (1- (window-max-chars-per-line window)))
                                  :graphic (display-graphic-p (window-frame window))
                                  :char-width (frame-char-width (window-frame window))
                                  :line-height (frame-char-height (window-frame window)))))
      (with-current-buffer buffer
        (agent-ui-review-preview-mode)
        (setq agent-ui-review--type name)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (agent-ui-review--heading (format "%s, made by the agent" name))
                  (agent-ui-type-doc type) "\n\n"
                  (agent-ui-review--heading "Properties"))
          (if (agent-ui-type-props type)
              (dolist (prop (agent-ui-type-props type))
                (insert (format "  %-12s %-28s %s%s\n"
                                (substring (symbol-name (agent-ui-prop-key prop)) 1)
                                (agent-ui--kind-name (agent-ui-prop-kind prop))
                                (agent-ui-prop-doc prop)
                                (cond ((agent-ui-prop-required prop) " (required)")
                                      ((agent-ui-prop-default prop)
                                       (format " (default %s)" (agent-ui--show-value
                                                               (agent-ui-to-json (agent-ui-prop-default prop)))))
                                      (t "")))))
            (insert "  none\n"))
          (insert "\n" (agent-ui-review--heading "Its example")
                  (agent-ui-even-glyphs
                   (agent-ui-render (append (list :type (symbol-name name)) (agent-ui-type-example type)) ctx))
                  "\n\n" (agent-ui-review--heading (format "Its code (%s)" (abbreviate-file-name file)))
                  (agent-ui-review--code file))
          (goto-char (point-min))))
      buffer)))

(defun agent-ui-review-source ()
  "Visit the code of the type at point (read-only)."
  (interactive)
  (let ((file (agent-ui--staged-file (agent-ui-review--name))))
    (with-current-buffer (find-file-other-window file)
      (read-only-mode 1))))

;; ====== KEEP, DISCARD ======

(defun agent-ui-review--close-preview (name)
  (when-let* ((buffer (get-buffer (format "Agent UI type: %s" name))))
    (quit-windows-on buffer t)))

(defun agent-ui-review-keep (&optional name)
  "Keep the type NAME (at point), asked first: it's loaded at each start
from now on (`agent-ui-keep')."
  (interactive)
  (let ((name (or name (agent-ui-review--name))))
    (when (or (not (called-interactively-p 'any))
              (y-or-n-p (format "Keep the type %s (loaded at each start)? " name)))
      (let ((file (agent-ui-keep name)))
        (agent-ui-review--close-preview name)
        (agent-ui-review--refresh)
        (message "Agent UI: %s kept, in %s" name (abbreviate-file-name file))
        file))))

(defun agent-ui-review-discard (&optional name)
  "Discard the type NAME (at point), asked first: its file deleted, the
elements of it removed (`agent-ui-discard')."
  (interactive)
  (let ((name (or name (agent-ui-review--name))))
    (when (or (not (called-interactively-p 'any))
              (y-or-n-p (format "Discard the type %s (its file deleted, its elements removed)? " name)))
      (agent-ui-discard name)
      (agent-ui-review--close-preview name)
      (agent-ui-review--refresh)
      (message "Agent UI: %s discarded" name)
      name)))

;; ====== THE CANVAS SAYS SO ======

(defun agent-ui-review--header ()
  "A canvas's header while types the agent made wait for review (nil else)."
  (when-let* ((files (agent-ui-staged-files)))
    (let ((names (mapcar #'file-name-base files)))
      (concat " "
              (propertize (format "%d type%s made by the agent to review: %s"
                                  (length names) (if (cdr names) "s" "") (string-join names ", "))
                          'face 'agent-ui-warning)
              (substitute-command-keys "   \\<agent-ui-canvas-mode-map>\\[agent-ui-review] review")))))

(defun agent-ui-review--canvas-header ()
  "The current canvas's header: none while no type waits (not an empty line)."
  (setq header-line-format (agent-ui-review--header)))

(defun agent-ui-review--canvas-headers ()
  (dolist (canvas (agent-ui-canvases))
    (with-current-buffer canvas (agent-ui-review--canvas-header))))

(add-hook 'agent-ui-canvas-hook #'agent-ui-review--canvas-header)
(keymap-set agent-ui-canvas-mode-map "R" #'agent-ui-review)

(defun agent-ui-review--staged (name)
  "The agent staged NAME: said, the list and the headers redrawn."
  (agent-ui-review--refresh)
  (message "Agent UI: the agent made a type, %s; review it with M-x agent-ui-review (R in its canvas)" name))

(add-hook 'agent-ui-staged-functions #'agent-ui-review--staged)
