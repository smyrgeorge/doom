;;; $DOOMDIR/config/editor/actions.el -*- lexical-binding: t; -*-
;; Context actions on Option+Enter (M-RET).
;; Loaded from config/editor.el.

(defvar +spell-correct-interface)       ; Doom's :checkers spell

(defun +my/context-actions--spell-suggestions ()
  "Return aspell's suggestions for the word at point."
  (let ((+spell-correct-interface (lambda (candidates _word)
                                    (throw '+my/suggestions candidates)))
        (inhibit-message t))
    (save-excursion
      (catch '+my/suggestions
        (ignore-errors (+spell/correct))
        nil))))

(defun +my/context-actions-spelling ()
  "Spelling actions, when spell-fu marked the word at point as misspelled."
  (when-let* (((fboundp '+spell/correct))
              (bounds (bounds-of-thing-at-point 'word))
              ((seq-some (lambda (ov) (overlay-get ov 'spell-fu-mode))
                         (overlays-in (car bounds) (cdr bounds)))))
    (let ((word (buffer-substring-no-properties (car bounds) (cdr bounds))))
      (append
       (mapcar (lambda (suggestion)
                 (list "Spelling" (format "Change to \"%s\"" suggestion)
                       (lambda ()
                         (let ((+spell-correct-interface (lambda (&rest _) suggestion)))
                           (+spell/correct)))))
               (seq-take (+my/context-actions--spell-suggestions)
                         +my/context-actions-max-suggestions))
       (list (list "Spelling" (format "Add \"%s\" to dictionary" word)
                   (lambda () (call-interactively #'+spell/add-word))))))))

(defun +my/context-actions-lsp ()
  "The LSP server's code actions for point or the active region."
  (when (bound-and-true-p lsp-mode)
    (mapcar (lambda (action)
              (list "Code actions" (lsp:code-action-title action)
                    (lambda () (lsp-execute-code-action action))))
            (append (ignore-errors (lsp-code-actions-at-point)) nil))))

(defun +my/context-actions--error-at-point-p ()
  "Non-nil if flycheck or flymake reports an error/warning at point."
  (or (and (bound-and-true-p flycheck-mode)
           (fboundp 'flycheck-overlay-errors-at)
           (flycheck-overlay-errors-at (point)))
      (and (bound-and-true-p flymake-mode)
           (flymake-diagnostics (point)))))

(defun +my/context-actions--with-region (bounds fn)
  "Call FN with the region BOUNDS (BEG . END) active, as when the menu opened."
  (save-excursion
    (goto-char (cdr bounds))
    (set-mark (car bounds))
    (activate-mark)
    (funcall fn)))

(defun +my/context-actions--agent ()
  "The agent a prompt sent from here goes to, as the actions name it: the
project's session's (its config's name: Claude, Codex), else your agent's
\(`agent-shell-preferred-agent-config'); \"the agent\" when not known
\(agent-shell not loaded yet)."
  (or (and (featurep 'agent-shell)
           (or (when-let* ((shell (car (ignore-errors (agent-shell-project-buffers)))))
                 (map-nested-elt (buffer-local-value 'agent-shell--state shell) '(:agent-config :mode-line-name)))
               (map-elt (ignore-errors (agent-shell--resolve-preferred-config)) :mode-line-name)))
      "the agent"))

(defun +my/agent-shell-ask (instruction context-fn)
  "Submit INSTRUCTION plus the context from CONTEXT-FN to the project's
session, whatever its agent. CONTEXT-FN runs in the current buffer with the
project directory as argument and returns agent-shell's context text (a
file:line link plus the code or the diagnostic). Starts a session with your
agent if the project has none; if it's busy, the prompt is queued and sent
when it finishes."
  (require 'agent-shell)
  ;; The project's true name, as the buffer's file has (Doom's
  ;; `find-file-visit-truename'): through a link, the file's path relative to
  ;; it was ../../../private/var/...
  (let* ((cwd (agent-shell-cwd))
         (context (or (funcall context-fn (and cwd (file-truename cwd)))
                      (user-error "Nothing to send")))
         (text (concat instruction "\n\n" context))
         (name (+my/context-actions--agent))
         (shell (agent-shell-shell-buffer)))
    (if (with-current-buffer shell (shell-maker-busy))
        (with-current-buffer shell
          (agent-shell-prompt-queue text)
          (message "%s is busy: prompt queued" (concat (upcase (substring name 0 1)) (substring name 1))))
      (agent-shell-insert :text text :submit t :shell-buffer shell))))

(define-obsolete-function-alias '+my/claude-ask #'+my/agent-shell-ask "2026-11-24")

(defun +my/context-actions-agent-shell ()
  "The agent's actions (agent-shell's) for the error or selection at point,
named for it (`+my/context-actions--agent')."
  (when (fboundp 'agent-shell)
    (let* ((region (and (region-active-p) (cons (region-beginning) (region-end))))
           (error-context (lambda (_cwd) (agent-shell--get-error-context)))
           (name (+my/context-actions--agent))
           (group (if (equal name "the agent") "Agent" name))
           (items nil))
      (when (+my/context-actions--error-at-point-p)
        (push (list group (format "Fix error with %s" name)
                    (lambda () (+my/agent-shell-ask "Fix this error:" error-context)))
              items)
        (push (list group (format "Explain error with %s" name)
                    (lambda () (+my/agent-shell-ask "Explain this error and how to fix it. Don't change any files."
                                                    error-context)))
              items))
      (if region
          (let ((region-context
                 (lambda (cwd)
                   (+my/context-actions--with-region
                    region (lambda () (agent-shell--get-region-context
                                       :deactivate t :no-error t :agent-cwd cwd))))))
            (push (list group (format "Explain selection with %s" name)
                        (lambda () (+my/agent-shell-ask "Explain this code. Don't change any files."
                                                        region-context)))
                  items)
            (push (list group (format "Add selection to %s's prompt" name)
                        (lambda () (+my/context-actions--with-region
                                    region #'agent-shell-send-region)))
                  items))
        (when buffer-file-name
          (push (list group (format "Add file to %s's prompt" name) #'agent-shell-send-file)
                items)))
      (nreverse items))))

(define-obsolete-function-alias '+my/context-actions-claude #'+my/context-actions-agent-shell "2026-11-24")

(defun +my/context-actions--collect ()
  "Return all actions at point, from `+my/context-action-providers'."
  (mapcan (lambda (provider) (copy-sequence (funcall provider)))
          +my/context-action-providers))

(defun +my/context-actions ()
  "Show the actions available at point (Option+Enter)."
  (interactive)
  (let ((actions (+my/context-actions--collect))
        (table nil))
    (unless actions
      (user-error "No actions here"))
    ;; Unique labels (completion returns a string), grouped in vertico.
    (dolist (action actions)
      (let* ((label (nth 1 action))
             (n 1))
        (while (assoc label table)
          (setq n (1+ n)
                label (format "%s <%d>" (nth 1 action) n)))
        (push (cons (propertize label '+my/group (nth 0 action)) action) table)))
    (setq table (nreverse table))
    (let* ((choice
            (completing-read
             "Action: "
             (lambda (string pred action)
               (if (eq action 'metadata)
                   `(metadata
                     (display-sort-function . identity)
                     (cycle-sort-function . identity)
                     (group-function
                      . ,(lambda (cand transform)
                           (if transform cand (get-text-property 0 '+my/group cand)))))
                 (complete-with-action action table string pred)))
             nil t)))
      ;; An empty answer (in vertico, M-RET again exits with the input as
      ;; typed) picks nothing.
      (when-let* ((action (cdr (assoc choice table))))
        (funcall (nth 2 action))))))
