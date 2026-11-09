;;; $DOOMDIR/config/agent-ui/persist.el -*- lexical-binding: t; -*-
;; Agent UI's canvases kept with their sessions: back when a session is
;; resumed. Loaded from config/agent-ui.el, after agent.el. No Doom here.
;;
;; A session's canvas is data, its elements: as they change, saved (a moment
;; later, together) as JSON in the session's .agent-shell/agent-ui/, named by
;; its ACP session id, beside agent-shell's transcripts. When a session
;; starts with that id (resumed: SPC o C with C-u C-u, agent-shell's
;; restart), its canvas comes back, as it was. Its elements' sources aren't
;; started again (a command run twice): they come back as they last were.
;; Closing a canvas, or its session, doesn't change what's saved; clearing it
;; does (an empty canvas, saved).

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-persist-directory ".agent-shell/agent-ui/"
  "Where sessions' canvases are kept, in a session's directory."
  :type 'string :group 'agent-ui)

(defcustom agent-ui-persist-delay 1.0
  "Seconds after a canvas's change before it's saved (changes within it
saved together)."
  :type 'number :group 'agent-ui)

(defvar-local agent-ui--persist-timer nil "In a canvas: its save, waiting.")

(declare-function agent-shell-session-id "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")

;; ====== WHERE ======

(defun agent-ui-persist-file (session)
  "Where SESSION's (an agent-shell buffer) canvas is kept: nil while it has
no session id."
  (when-let* (((buffer-live-p session))
              ((fboundp 'agent-shell-session-id))
              (id (agent-shell-session-id :shell-buffer session))
              ((not (string-empty-p id))))
    (expand-file-name (concat (replace-regexp-in-string "[^A-Za-z0-9_.-]" "_" id) ".json")
                      (expand-file-name agent-ui-persist-directory (agent-ui--session-cwd session)))))

;; ====== SAVING ======

(defun agent-ui-persist-save (&optional canvas)
  "Save CANVAS (default: the current buffer's), if it has a session with an
id: its elements, as JSON. Returns the file, or nil."
  (with-current-buffer (or canvas (current-buffer))
    (when (timerp agent-ui--persist-timer)
      (cancel-timer agent-ui--persist-timer))
    (setq agent-ui--persist-timer nil)
    (when-let* ((file (agent-ui-persist-file agent-ui--session-buffer)))
      (let ((elements (mapcar (lambda (id) (agent-ui--entry-element (gethash id agent-ui--entries)))
                              agent-ui--order)))
        (make-directory (file-name-directory file) t)
        (let ((coding-system-for-write 'utf-8))
          (write-region (decode-coding-string
                         (json-serialize (vconcat (mapcar #'agent-ui-to-json elements))) 'utf-8)
                        nil file nil 'silent))
        file))))

(defun agent-ui--persist-later ()
  "The current canvas changed: saved `agent-ui-persist-delay' from now."
  (when (and agent-ui--session-buffer (not agent-ui--persist-timer))
    (let ((canvas (current-buffer)))
      (setq agent-ui--persist-timer
            (run-with-timer agent-ui-persist-delay nil
                            (lambda ()
                              (when (buffer-live-p canvas)
                                (agent-ui-persist-save canvas))))))))

(defun agent-ui--persist-closing ()
  "The canvas closes: what's waiting saved now (what's saved stays)."
  (when (timerp agent-ui--persist-timer)
    (agent-ui-persist-save (current-buffer))))

(add-hook 'agent-ui-changed-hook #'agent-ui--persist-later)
(add-hook 'agent-ui-canvas-hook
          (lambda () (add-hook 'kill-buffer-hook #'agent-ui--persist-closing -50 t)))

;; ====== RESTORING ======

(defun agent-ui-persist--without-sources (element)
  "ELEMENT without its source, nor its panel's children theirs."
  (let ((element (agent-ui--plist-delete element :source)))
    (if-let* ((children (plist-get element :children)))
        (plist-put element :children (mapcar (lambda (c) (if (agent-ui--plist-p c) (agent-ui-persist--without-sources c) c))
                                             children))
      element)))

(defun agent-ui-persist-restore (session)
  "SESSION's canvas back (an agent-shell buffer whose session id is known),
if one was kept and its canvas is empty: its elements shown again, their
sources not started. Returns how many."
  (when-let* ((file (agent-ui-persist-file session))
              ((file-readable-p file))
              (name (agent-ui--session-name session))
              ((not (agent-ui-elements :canvas name))))
    (let ((elements (condition-case nil
                        (agent-ui-parse-json (with-temp-buffer
                                               (let ((coding-system-for-read 'utf-8))
                                                 (insert-file-contents file))
                                               (buffer-string)))
                      (agent-ui-error nil)))
          (count 0))
      (dolist (element elements)
        (when (agent-ui--plist-p element)
          (condition-case nil
              (progn (agent-ui-show (agent-ui-persist--without-sources element) :canvas name)
                     (cl-incf count))
            ;; One of a type gone since (discarded): left out.
            (agent-ui-error nil))))
      (when (> count 0)
        (message "Agent UI: this session's canvas, back (%d element%s)" count (if (= count 1) "" "s")))
      count)))

(defun agent-ui--persist-watch ()
  "In a new agent-shell buffer: its canvas back once its session is known."
  (when (fboundp 'agent-shell-subscribe-to)
    (let ((session (current-buffer)))
      (agent-shell-subscribe-to
       :shell-buffer session
       :event 'init-session
       :on-event (lambda (_event)
                   (condition-case err
                       (agent-ui-persist-restore session)
                     (error (message "Agent UI: the canvas couldn't come back: %s"
                                     (error-message-string err)))))))))

(add-hook 'agent-shell-mode-hook #'agent-ui--persist-watch)
