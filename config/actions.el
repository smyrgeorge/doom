;;; $DOOMDIR/config/actions.el -*- lexical-binding: t; -*-
;; Context actions on Option+Enter (M-RET), like Alt+Enter in JetBrains IDEs.
;; Loaded from config.el.

;; CONTEXT ACTIONS
;; One menu (grouped, in vertico) with everything that applies at point:
;; - Spelling: suggestions and "add to dictionary", when spell-fu flagged the
;;   word at point.
;; - Code actions: the LSP server's quick fixes and refactors for the point or
;;   the active region (same list as SPC c a).
;;
;; Each section comes from a provider: a function that returns a list of
;; (GROUP LABEL FUNCTION). To add more (e.g. AI actions), write a provider and
;; (add-to-list '+my/context-action-providers #'my-provider t).
(defvar +my/context-action-providers
  '(+my/context-actions-spelling
    +my/context-actions-lsp)
  "Functions returning the actions available at point, as (GROUP LABEL FUNCTION).
The menu shows groups in this order.")

(defvar +my/context-actions-max-suggestions 5
  "How many spelling suggestions to show (aspell lists the likeliest first).")

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
      (funcall (nth 2 (cdr (assoc choice table)))))))

(map! :ni "M-RET" #'+my/context-actions)
;; Org keeps M-RET for "new heading/item".
(map! :after org :map org-mode-map :ni "M-RET" #'org-meta-return)
