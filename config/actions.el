;;; $DOOMDIR/config/actions.el -*- lexical-binding: t; -*-
;; Context actions on Option+Enter (M-RET), like Alt+Enter in JetBrains IDEs.
;; Loaded from config.el.

;; ====== VARIABLES ======

;; CONTEXT ACTIONS
;; One menu (grouped, in vertico) with everything that applies at point:
;; - Spelling: suggestions and "add to dictionary", when spell-fu flagged the
;;   word at point.
;; - Code actions: the LSP server's quick fixes and refactors for the point or
;;   the active region (same list as SPC c a).
;; - Claude: send the error at point or the selection to Claude Code
;;   (agent-shell), either as a ready prompt (fix / explain) or into the prompt
;;   for you to finish.
;; - PDF: in a PDF (config/pdf-xwidget.el, which adds its provider first), for
;;   the selected text: copy, search the PDF or the web, Claude; Preview, print.
;;
;; Each section comes from a provider: a function that returns a list of
;; (GROUP LABEL FUNCTION). To add more, write a provider and
;; (add-to-list '+my/context-action-providers #'my-provider t).
(defvar +my/context-action-providers
  '(+my/context-actions-spelling
    +my/context-actions-lsp
    +my/context-actions-claude)
  "Functions returning the actions available at point, as (GROUP LABEL FUNCTION).
The menu shows groups in this order.")

(defvar +my/context-actions-max-suggestions 5
  "How many spelling suggestions to show (aspell lists the likeliest first).")

(defvar +spell-correct-interface)       ; Doom's :checkers spell

;; ====== KEY BINDINGS ======

;; Visual state too: code actions and Claude actions work on the selection.
(map! :nvi "M-RET" #'+my/context-actions)

;; Org keeps M-RET for "new heading/item".
(map! :after org :map org-mode-map :ni "M-RET" #'org-meta-return)

;; ====== CODE ======

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

(defun +my/claude-ask (instruction context-fn)
  "Submit INSTRUCTION plus the context from CONTEXT-FN to Claude Code.
CONTEXT-FN runs in the current buffer with the project directory as argument
and returns agent-shell's context text (a file:line link plus the code or the
diagnostic). Starts a Claude shell if the project has none; if Claude is busy,
the prompt is queued and sent when it finishes."
  (require 'agent-shell)
  ;; The project's true name, as the buffer's file has (Doom's
  ;; `find-file-visit-truename'): through a link, the file's path relative to
  ;; it was ../../../private/var/...
  (let* ((cwd (agent-shell-cwd))
         (context (or (funcall context-fn (and cwd (file-truename cwd)))
                      (user-error "Nothing to send")))
         (text (concat instruction "\n\n" context))
         (shell (agent-shell-shell-buffer)))
    (if (with-current-buffer shell (shell-maker-busy))
        (with-current-buffer shell
          (agent-shell-prompt-queue text)
          (message "Claude is busy: prompt queued"))
      (agent-shell-insert :text text :submit t :shell-buffer shell))))

(defun +my/context-actions-claude ()
  "Claude Code (agent-shell) actions for the error or selection at point."
  (when (fboundp 'agent-shell)
    (let ((region (and (region-active-p) (cons (region-beginning) (region-end))))
          (error-context (lambda (_cwd) (agent-shell--get-error-context)))
          (items nil))
      (when (+my/context-actions--error-at-point-p)
        (push (list "Claude" "Fix error with Claude"
                    (lambda () (+my/claude-ask "Fix this error:" error-context)))
              items)
        (push (list "Claude" "Explain error with Claude"
                    (lambda () (+my/claude-ask "Explain this error and how to fix it. Don't change any files."
                                               error-context)))
              items))
      (if region
          (let ((region-context
                 (lambda (cwd)
                   (+my/context-actions--with-region
                    region (lambda () (agent-shell--get-region-context
                                       :deactivate t :no-error t :agent-cwd cwd))))))
            (push (list "Claude" "Explain selection with Claude"
                        (lambda () (+my/claude-ask "Explain this code. Don't change any files."
                                                   region-context)))
                  items)
            (push (list "Claude" "Add selection to Claude prompt"
                        (lambda () (+my/context-actions--with-region
                                    region #'agent-shell-send-region)))
                  items))
        (when buffer-file-name
          (push (list "Claude" "Add file to Claude prompt" #'agent-shell-send-file)
                items)))
      (nreverse items))))

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
