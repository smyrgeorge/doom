;;; tests/unit/test-actions.el -*- lexical-binding: t; -*-
;; config/editor/actions.el: Option+Enter (M-RET), one menu with the actions at point
;; like JetBrains' Alt+Enter, from providers: spelling, the language server's
;; code actions, Claude (agent-shell). Org keeps M-RET.
;; Nothing external runs: aspell, the language server and Claude are mocked.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

;; Org, if it loads, keeps its caches in the temp folder.
(defvar org-persist-directory (+test-tmp-file "org-persist/"))

(+test-load "config/editor")

(require 'agent-shell)
(require 'lsp-mode)
(require 'flymake)

;; ====== HELPERS ======

(defmacro +test-actions--in (content &rest body)
  "BODY in a buffer with CONTENT (point at its start), transient mark on."
  (declare (indent 1))
  `(+test-with-reset
     (let ((transient-mark-mode t))
       (with-current-buffer (+test-buffer "actions" ,content #'fundamental-mode)
         (switch-to-buffer (current-buffer))
         ,@body))))

(defun +test-actions--flag (beg end)
  "Mark BEG..END as misspelled, as spell-fu does."
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'spell-fu-mode t)
    (overlay-put ov 'face 'spell-fu-incorrect-face)
    ov))

(defvar +test-actions--aspell '("hello" "hell" "help" "held" "helm" "hollow" "jello")
  "What the mocked aspell suggests, likeliest first.")

(defmacro +test-actions--with-spell (&rest body)
  "BODY with Doom's `+spell/correct' and `+spell/add-word' mocked: correct
asks `+spell-correct-interface' to choose among `+test-actions--aspell' for
the word at point and puts the choice in its place (as Doom's does); `added'
gets the words added to the dictionary."
  (declare (indent 0))
  `(let ((added nil))
     (cl-letf (((symbol-function '+spell/correct)
                (lambda ()
                  (interactive)
                  (let* ((bounds (or (bounds-of-thing-at-point 'word)
                                     (user-error "No word at point")))
                         (word (buffer-substring-no-properties (car bounds) (cdr bounds)))
                         (choice (funcall +spell-correct-interface
                                          +test-actions--aspell word)))
                    (when (stringp choice)
                      (delete-region (car bounds) (cdr bounds))
                      (goto-char (car bounds))
                      (insert choice)))))
               ((symbol-function '+spell/add-word)
                (lambda ()
                  (interactive)
                  (push (thing-at-point 'word t) added))))
       ,@body)))

(defmacro +test-actions--with-claude (&rest body)
  "BODY with agent-shell mocked: `sent' gets agent-shell-insert's arguments,
`queued' the prompts queued, `busy' says whether Claude is busy, `shell' is
the project's shell buffer, `cwd' the project's folder."
  (declare (indent 0))
  `(let* ((sent nil)
          (queued nil)
          (busy nil)
          (cwd (file-name-as-directory (+test-tmp-file "claude-project/")))
          (shell (+test-buffer "Claude Agent @ project")))
     (ignore busy)
     (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () cwd))
               ((symbol-function 'agent-shell-shell-buffer) (lambda (&rest _) shell))
               ((symbol-function 'shell-maker-busy) (lambda () busy))
               ((symbol-function 'agent-shell-prompt-queue)
                (lambda (prompt) (push (cons (current-buffer) prompt) queued)))
               ((symbol-function 'agent-shell-insert)
                (lambda (&rest args) (push args sent))))
       ,@body)))

(defun +test-actions--find (actions label)
  "The action LABEL among ACTIONS."
  (seq-find (lambda (action) (equal (nth 1 action) label)) actions))

(defun +test-actions--run (actions label)
  "Run the action LABEL among ACTIONS."
  (let ((action (+test-actions--find actions label)))
    (should action)
    (funcall (nth 2 action))))

(defmacro +test-actions--menu (choose &rest body)
  "BODY with the menu's `completing-read' answered by CHOOSE, a function of
the candidates (in the menu's order) returning the choice. `menu' gets
\(PROMPT COLLECTION PREDICATE REQUIRE-MATCH) of the last menu."
  (declare (indent 1))
  `(let ((menu nil))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (prompt collection &optional predicate require-match &rest _)
                  (setq menu (list prompt collection predicate require-match))
                  (funcall ,choose (all-completions "" collection predicate)))))
       ,@body)))

(defun +test-actions--metadata (collection)
  (cdr (funcall collection "" nil 'metadata)))

;; ====== SETTINGS ======

(ert-deftest actions/providers-default ()
  "Spelling, code actions, Claude: the menu's groups in this order."
  (should (equal (default-value '+my/context-action-providers)
                 '(+my/context-actions-spelling
                   +my/context-actions-lsp
                   +my/context-actions-claude)))
  (dolist (provider +my/context-action-providers)
    (should (functionp provider))))

(ert-deftest actions/max-suggestions-default ()
  (should (eql (default-value '+my/context-actions-max-suggestions) 5)))

;; ====== KEYS ======

(ert-deftest actions/m-ret-in-normal-insert-and-visual ()
  (dolist (map (list evil-normal-state-map evil-insert-state-map evil-visual-state-map))
    (should (eq (lookup-key map (kbd "M-RET")) #'+my/context-actions)))
  (should (commandp #'+my/context-actions)))

(ert-deftest actions/m-ret-reaches-a-buffer ()
  (+test-actions--in "text"
    (evil-local-mode 1)
    (dolist (state '(normal insert visual))
      (evil-change-state state)
      (should (eq (key-binding (kbd "M-RET")) #'+my/context-actions)))
    (evil-normal-state)))

(ert-deftest actions/org-keeps-m-ret ()
  "Org: M-RET is a new heading/item in normal and insert state; the selection
still gets the actions."
  (require 'org)
  (should (eq (lookup-key (evil-get-auxiliary-keymap org-mode-map 'normal) (kbd "M-RET"))
              #'org-meta-return))
  (should (eq (lookup-key (evil-get-auxiliary-keymap org-mode-map 'insert) (kbd "M-RET"))
              #'org-meta-return))
  (+test-with-reset
    (with-current-buffer (+test-buffer "notes.org" "* Heading\n" #'org-mode)
      (switch-to-buffer (current-buffer))
      (evil-local-mode 1)
      (evil-normal-state)
      (should (eq (key-binding (kbd "M-RET")) #'org-meta-return))
      (evil-insert-state)
      (should (eq (key-binding (kbd "M-RET")) #'org-meta-return))
      (evil-visual-state)
      (should (eq (key-binding (kbd "M-RET")) #'+my/context-actions))
      (evil-normal-state))))

;; ====== SPELLING ======

(ert-deftest actions/spell-suggestions-are-aspells ()
  "The suggestions `+spell/correct' would offer, without its menu showing or
the word changing."
  (+test-actions--in "helo world"
    (+test-actions--with-spell
      (should (equal (+my/context-actions--spell-suggestions) +test-actions--aspell))
      (should (equal (buffer-string) "helo world"))
      (should (= (point) 1)))))

(ert-deftest actions/spell-suggestions-keep-point ()
  (+test-actions--in "say helo"
    (goto-char 6)
    (cl-letf (((symbol-function '+spell/correct)
               (lambda () (goto-char (point-max))
                 (funcall +spell-correct-interface '("hello") "helo"))))
      (should (equal (+my/context-actions--spell-suggestions) '("hello")))
      (should (= (point) 6)))))

(ert-deftest actions/spell-suggestions-silent ()
  "aspell's messages (e.g. \"helo is correct\") don't show."
  (+test-actions--in "helo"
    (let (inhibited)
      (cl-letf (((symbol-function '+spell/correct)
                 (lambda () (setq inhibited inhibit-message) (message "helo is correct") t)))
        (should-not (+my/context-actions--spell-suggestions))
        (should (eq inhibited t))))))

(ert-deftest actions/spell-suggestions-none-when-correct ()
  "A correct word: `+spell/correct' never asks, so no suggestions."
  (+test-actions--in "hello"
    (cl-letf (((symbol-function '+spell/correct) (lambda () t)))
      (should-not (+my/context-actions--spell-suggestions)))))

(ert-deftest actions/spell-suggestions-none-on-errors ()
  "aspell missing (Doom's user-error) or failing: no suggestions, no error."
  (+test-actions--in "helo"
    (cl-letf (((symbol-function '+spell/correct)
               (lambda () (user-error "Aspell is required for spell checking"))))
      (should-not (+my/context-actions--spell-suggestions)))
    (cl-letf (((symbol-function '+spell/correct)
               (lambda () (error "Ispell: error in Ispell process"))))
      (should-not (+my/context-actions--spell-suggestions)))))

(ert-deftest actions/spell-suggestions-restore-the-interface ()
  (+test-actions--in "helo"
    (let ((+spell-correct-interface 'my-interface))
      (+test-actions--with-spell
        (+my/context-actions--spell-suggestions))
      (should (eq +spell-correct-interface 'my-interface)))))

(ert-deftest actions/spelling-flagged-word ()
  "A word spell-fu flagged: the first 5 suggestions, then add to dictionary."
  (+test-actions--in "say helo now"
    (+test-actions--flag 5 9)
    (goto-char 6)
    (+test-actions--with-spell
      (let ((actions (+my/context-actions-spelling)))
        (should (equal (mapcar (lambda (a) (nth 1 a)) actions)
                       '("Change to \"hello\"" "Change to \"hell\"" "Change to \"help\""
                         "Change to \"held\"" "Change to \"helm\""
                         "Add \"helo\" to dictionary")))
        (dolist (action actions)
          (should (equal (nth 0 action) "Spelling"))
          (should (functionp (nth 2 action))))))))

(ert-deftest actions/spelling-at-the-words-edges ()
  "Point at the start or right after the end of the word counts."
  (+test-actions--in "say helo"
    (+test-actions--flag 5 9)
    (+test-actions--with-spell
      (dolist (pos '(5 9))
        (goto-char pos)
        (should (+test-actions--find (+my/context-actions-spelling)
                                     "Add \"helo\" to dictionary"))))))

(ert-deftest actions/spelling-suggestions-capped ()
  (+test-actions--in "helo"
    (+test-actions--flag 1 5)
    (+test-actions--with-spell
      (let ((+my/context-actions-max-suggestions 2))
        (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions-spelling))
                       '("Change to \"hello\"" "Change to \"hell\"" "Add \"helo\" to dictionary"))))
      (let ((+my/context-actions-max-suggestions 0))
        (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions-spelling))
                       '("Add \"helo\" to dictionary"))))
      (let ((+my/context-actions-max-suggestions 50))
        (should (= (length (+my/context-actions-spelling))
                   (1+ (length +test-actions--aspell))))))))

(ert-deftest actions/spelling-without-suggestions ()
  "aspell has none (or isn't there): still \"Add to dictionary\"."
  (+test-actions--in "qzxv"
    (+test-actions--flag 1 5)
    (let ((+test-actions--aspell nil))
      (+test-actions--with-spell
        (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions-spelling))
                       '("Add \"qzxv\" to dictionary")))))
    (cl-letf (((symbol-function '+spell/correct) (lambda () (user-error "Aspell is required")))
              ((symbol-function '+spell/add-word) #'ignore))
      (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions-spelling))
                     '("Add \"qzxv\" to dictionary"))))))

(ert-deftest actions/spelling-change-replaces-the-word ()
  (+test-actions--in "say helo now"
    (+test-actions--flag 5 9)
    (goto-char 6)
    (+test-actions--with-spell
      (let ((actions (+my/context-actions-spelling)))
        (+test-actions--run actions "Change to \"help\"")
        (should (equal (buffer-string) "say help now"))))))

(ert-deftest actions/spelling-change-asks-nothing ()
  "The change goes straight in: `+spell/correct' gets the suggestion, not a
menu (whatever the interface was)."
  (+test-actions--in "helo"
    (+test-actions--flag 1 5)
    (let ((asked nil))
      (cl-letf (((symbol-function '+spell/correct)
                 (lambda () (push (funcall +spell-correct-interface '("other") "helo") asked)))
                ((symbol-function '+spell/add-word) #'ignore)
                ((symbol-function '+my/context-actions--spell-suggestions)
                 (lambda () '("hello"))))
        (+test-actions--run (+my/context-actions-spelling) "Change to \"hello\"")
        (should (equal asked '("hello")))))))

(ert-deftest actions/spelling-add-to-dictionary ()
  (+test-actions--in "say helo"
    (+test-actions--flag 5 9)
    (goto-char 6)
    (+test-actions--with-spell
      (+test-actions--run (+my/context-actions-spelling) "Add \"helo\" to dictionary")
      (should (equal added '("helo")))
      (should (equal (buffer-string) "say helo")))))

(ert-deftest actions/spelling-add-to-dictionary-interactively ()
  "spell-fu's `spell-fu-word-add' is a command reading its arguments: called
interactively."
  (+test-actions--in "helo"
    (+test-actions--flag 1 5)
    (let (interactive)
      (cl-letf (((symbol-function '+spell/correct) #'ignore)
                ((symbol-function '+spell/add-word)
                 (lambda () (interactive) (setq interactive (called-interactively-p 'any)))))
        (+test-actions--run (+my/context-actions-spelling) "Add \"helo\" to dictionary")
        (should interactive)))))

(ert-deftest actions/spelling-only-on-flagged-words ()
  "Nothing for a word spell-fu didn't flag, another word's flag, or a flag of
something else."
  (+test-actions--in "say helo now"
    (+test-actions--with-spell
      (goto-char 6)
      (should-not (+my/context-actions-spelling))       ; nothing flagged
      (+test-actions--flag 10 13)                       ; "now"
      (should-not (+my/context-actions-spelling))
      (let ((ov (make-overlay 5 9)))                   ; another overlay
        (overlay-put ov 'face 'error)
        (should-not (+my/context-actions-spelling))))))

(ert-deftest actions/spelling-not-off-a-word ()
  (+test-actions--in "helo    \n"
    (+test-actions--flag 1 5)
    (+test-actions--with-spell
      (goto-char 7)
      (should-not (+my/context-actions-spelling))
      (goto-char (point-max))
      (should-not (+my/context-actions-spelling)))))

(ert-deftest actions/spelling-without-dooms-spell-module ()
  "No `+spell/correct' (spell module off): no spelling actions."
  (+test-actions--in "helo"
    (+test-actions--flag 1 5)
    (cl-letf (((symbol-function '+spell/correct) nil))
      (should-not (fboundp '+spell/correct))
      (should-not (+my/context-actions-spelling)))))

(ert-deftest actions/spelling-camel-case-part ()
  "In an identifier, the part spell-fu flagged (camelCase checked word by
word: config/spell.el): `word' at point is the whole identifier, which is
what the actions name."
  (+test-actions--in "getHelo()"
    (+test-actions--flag 4 8)
    (goto-char 5)
    (+test-actions--with-spell
      (should (+test-actions--find (+my/context-actions-spelling)
                                   "Add \"getHelo\" to dictionary")))))

;; ====== CODE ACTIONS ======

(ert-deftest actions/lsp-only-with-a-server ()
  (+test-actions--in "code"
    (let ((asked nil))
      (cl-letf (((symbol-function 'lsp-code-actions-at-point)
                 (lambda (&rest _) (setq asked t) (list (lsp-make-code-action :title "Fix")))))
        (should-not (+my/context-actions-lsp))
        (should-not asked)
        (setq-local lsp-mode nil)
        (should-not (+my/context-actions-lsp))
        (should-not asked)))))

(ert-deftest actions/lsp-code-actions ()
  "The server's code actions, its titles, in its order."
  (+test-actions--in "code"
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-code-actions-at-point)
               (lambda (&rest _) (list (lsp-make-code-action :title "Import java.util.List")
                                       (lsp-make-code-action :title "Extract method")))))
      (let ((actions (+my/context-actions-lsp)))
        (should (equal (mapcar (lambda (a) (nth 1 a)) actions)
                       '("Import java.util.List" "Extract method")))
        (dolist (action actions)
          (should (equal (nth 0 action) "Code actions")))))))

(ert-deftest actions/lsp-code-actions-vector ()
  "lsp-mode hands JSON arrays over as vectors."
  (+test-actions--in "code"
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-code-actions-at-point)
               (lambda (&rest _) (vector (lsp-make-code-action :title "A")
                                         (lsp-make-code-action :title "B")))))
      (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions-lsp))
                     '("A" "B"))))))

(ert-deftest actions/lsp-none ()
  (+test-actions--in "code"
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-code-actions-at-point) (lambda (&rest _) nil)))
      (should-not (+my/context-actions-lsp)))
    (cl-letf (((symbol-function 'lsp-code-actions-at-point) (lambda (&rest _) [])))
      (should-not (+my/context-actions-lsp)))))

(ert-deftest actions/lsp-server-errors-ignored ()
  "A server that fails (or times out) leaves the other actions."
  (+test-actions--in "code"
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-code-actions-at-point)
               (lambda (&rest _) (error "Timeout while waiting for response"))))
      (should-not (+my/context-actions-lsp)))))

(ert-deftest actions/lsp-action-runs-it ()
  (+test-actions--in "code"
    (setq-local lsp-mode t)
    (let* ((fix (lsp-make-code-action :title "Fix it"))
           (other (lsp-make-code-action :title "Other"))
           (executed nil))
      (cl-letf (((symbol-function 'lsp-code-actions-at-point) (lambda (&rest _) (list fix other)))
                ((symbol-function 'lsp-execute-code-action)
                 (lambda (action) (push action executed))))
        (+test-actions--run (+my/context-actions-lsp) "Fix it")
        (should (equal executed (list fix)))))))

(ert-deftest actions/lsp-region ()
  "With a selection, the server's actions for it (lsp-mode reads the region)."
  (+test-actions--in "some code here"
    (setq-local lsp-mode t)
    (set-mark 6)
    (goto-char 10)
    (activate-mark)
    (let (region)
      (cl-letf (((symbol-function 'lsp-code-actions-at-point)
                 (lambda (&rest _)
                   (setq region (and (region-active-p) (cons (region-beginning) (region-end))))
                   nil)))
        (+my/context-actions-lsp)
        (should (equal region '(6 . 10)))))))

;; ====== ERRORS AT POINT ======

(ert-deftest actions/error-at-point-flycheck ()
  (+test-actions--in "code"
    (let ((errors '(error-1)))
      (cl-letf (((symbol-function 'flycheck-overlay-errors-at) (lambda (_pos) errors)))
        (setq-local flycheck-mode t)
        (should (+my/context-actions--error-at-point-p))
        (setq errors nil)
        (should-not (+my/context-actions--error-at-point-p))
        (setq errors '(e))
        (setq-local flycheck-mode nil)
        (should-not (+my/context-actions--error-at-point-p))))))

(ert-deftest actions/error-at-point-flycheck-not-loaded ()
  (+test-actions--in "code"
    (setq-local flycheck-mode t)
    (cl-letf (((symbol-function 'flycheck-overlay-errors-at) nil))
      (should-not (+my/context-actions--error-at-point-p)))))

(ert-deftest actions/error-at-point-flymake ()
  (+test-actions--in "code"
    (let ((diagnostics '(d)))
      (cl-letf (((symbol-function 'flymake-diagnostics) (lambda (&rest _) diagnostics)))
        (setq-local flymake-mode t)
        (should (+my/context-actions--error-at-point-p))
        (setq diagnostics nil)
        (should-not (+my/context-actions--error-at-point-p))
        (setq diagnostics '(d))
        (setq-local flymake-mode nil)
        (should-not (+my/context-actions--error-at-point-p))))))

(ert-deftest actions/error-at-point-real-flymake ()
  "Flymake's own diagnostics, only where they are."
  (+test-actions--in "good bad good"
    (setq-local flymake-diagnostic-functions
                (list (lambda (report &rest _)
                        (funcall report (list (flymake-make-diagnostic
                                               (current-buffer) 6 9 :error "bad word"))))))
    (flymake-mode 1)
    (flymake-start)
    (goto-char 7)
    (should (+my/context-actions--error-at-point-p))
    (goto-char 2)
    (should-not (+my/context-actions--error-at-point-p))
    (flymake-mode -1)))

(ert-deftest actions/error-at-point-none ()
  (+test-actions--in "code"
    (should-not (+my/context-actions--error-at-point-p))))

;; ====== THE REGION ======

(ert-deftest actions/with-region ()
  "FN runs with BOUNDS as the active region, point at its end; point is back
after."
  (+test-actions--in "0123456789"
    (goto-char 2)
    (let (seen)
      (should (eq (+my/context-actions--with-region
                   '(4 . 8)
                   (lambda () (setq seen (list (region-active-p) (region-beginning)
                                               (region-end) (point)))
                     'result))
                  'result))
      (should (equal seen '(t 4 8 8)))
      (should (= (point) 2)))))

(ert-deftest actions/with-region-after-it-was-lost ()
  "The selection back, as when the menu opened, though it's gone since."
  (+test-actions--in "0123456789"
    (set-mark 1)
    (goto-char 3)
    (deactivate-mark)
    (let (seen)
      (+my/context-actions--with-region
       '(5 . 10) (lambda () (setq seen (buffer-substring (region-beginning) (region-end)))))
      (should (equal seen "45678")))))

;; ====== CLAUDE: SENDING ======

(ert-deftest actions/claude-ask-submits ()
  "The instruction, a blank line, the context: submitted to the project's
shell; the context made with the project's folder."
  (+test-actions--in "code"
    (+test-actions--with-claude
      (let (got-cwd)
        (+my/claude-ask "Fix this error:"
                        (lambda (dir) (setq got-cwd dir) "code.el:1: error: bad"))
        ;; The project's true name, as the buffer's file has (a link in its
        ;; path made its file ../../private/var/... relative to it).
        (should (equal got-cwd (file-truename cwd)))
        (should (equal sent (list (list :text "Fix this error:\n\ncode.el:1: error: bad"
                                        :submit t :shell-buffer shell))))
        (should-not queued)))))

(ert-deftest actions/claude-ask-context-in-the-buffer ()
  "The context is made in the buffer the menu was opened in."
  (+test-actions--in "code"
    (+test-actions--with-claude
      (let ((buffer (current-buffer)) in)
        (+my/claude-ask "Explain:" (lambda (_) (setq in (current-buffer)) "x"))
        (should (eq in buffer))))))

(ert-deftest actions/claude-ask-busy-queues ()
  "Claude busy: queued in its shell (sent when it finishes), and said so."
  (+test-actions--in "code"
    (+test-actions--with-claude
      (setq busy t)
      (+test-clear-messages)
      (+my/claude-ask "Fix this error:" (lambda (_) "ctx"))
      (should-not sent)
      (should (equal queued (list (cons shell "Fix this error:\n\nctx"))))
      (should (= (+test-messages "^Claude is busy: prompt queued$") 1)))))

(ert-deftest actions/claude-ask-busy-is-the-shells ()
  "Busy is asked of the shell buffer (shell-maker's state is buffer-local)."
  (+test-actions--in "code"
    (+test-actions--with-claude
      (let (asked-in)
        (cl-letf (((symbol-function 'shell-maker-busy)
                   (lambda () (setq asked-in (current-buffer)) nil)))
          (+my/claude-ask "Explain:" (lambda (_) "ctx"))
          (should (eq asked-in shell))
          (should sent))))))

(ert-deftest actions/claude-ask-nothing-to-send ()
  (+test-actions--in "code"
    (+test-actions--with-claude
      (let ((err (should-error (+my/claude-ask "Fix this error:" (lambda (_) nil))
                               :type 'user-error)))
        (should (equal (cadr err) "Nothing to send")))
      (should-not sent)
      (should-not queued))))

(ert-deftest actions/claude-ask-starts-claude-code-if-none ()
  "No shell in the project: agent-shell starts one, Claude Code without asking
(config/agent-shell.el's default agent), in the project's folder."
  (+test-actions--in "code"
    (let ((cwd (file-name-as-directory (+test-tmp-file "claude-project/")))
          (new (+test-buffer "Claude Agent @ new"))
          (agent-shell-preferred-agent-config 'claude-code)
          (agent-shell-session-strategy 'prompt)
          (agent-shell-prefer-viewport-interaction nil)
          started sent)
      (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () cwd))
                ((symbol-function 'agent-shell-project-buffers) (lambda (&rest _) nil))
                ((symbol-function 'agent-shell-select-config)
                 (lambda (&rest _) (error "Asked which agent to use")))
                ((symbol-function 'agent-shell--start)
                 (lambda (&rest args) (push args started) new))
                ((symbol-function 'shell-maker-busy) (lambda () nil))
                ((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args sent))))
        (+my/claude-ask "Explain:" (lambda (_) "ctx")))
      (should (= (length started) 1))
      (should (eq (map-elt (plist-get (car started) :config) :identifier) 'claude-code))
      (should (equal (plist-get (car started) :cwd) cwd))
      (should (eq (plist-get (car sent) :shell-buffer) new)))))

;; ====== CLAUDE: THE ACTIONS ======

(ert-deftest actions/claude-nothing-in-a-plain-buffer ()
  "No error, no selection, no file: no Claude actions."
  (+test-actions--in "text"
    (should-not (+my/context-actions-claude))))

(ert-deftest actions/claude-without-agent-shell ()
  (+test-actions--in "text"
    (setq buffer-file-name (+test-tmp-file "a.el"))
    (set-mark 1) (goto-char 3) (activate-mark)
    (cl-letf (((symbol-function 'agent-shell) nil)
              ((symbol-function '+my/context-actions--error-at-point-p) (lambda () t)))
      (should-not (+my/context-actions-claude)))
    (setq buffer-file-name nil)))

(defun +test-actions--labels (actions)
  (mapcar (lambda (a) (nth 1 a)) actions))

(ert-deftest actions/claude-in-a-file ()
  (+test-actions--in "code"
    (setq buffer-file-name (+test-tmp-file "a.el"))
    (let ((actions (+my/context-actions-claude)))
      (should (equal (+test-actions--labels actions) '("Add file to Claude prompt")))
      (should (equal (car (car actions)) "Claude"))
      (should (eq (nth 2 (car actions)) #'agent-shell-send-file)))
    (setq buffer-file-name nil)))

(ert-deftest actions/claude-on-an-error ()
  "On an error: fix and explain it, then the file."
  (+test-actions--in "code"
    (setq buffer-file-name (+test-tmp-file "a.el"))
    (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t)))
      (should (equal (+test-actions--labels (+my/context-actions-claude))
                     '("Fix error with Claude" "Explain error with Claude"
                       "Add file to Claude prompt"))))
    (setq buffer-file-name nil)))

(ert-deftest actions/claude-on-an-error-outside-files ()
  (+test-actions--in "code"
    (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t)))
      (should (equal (+test-actions--labels (+my/context-actions-claude))
                     '("Fix error with Claude" "Explain error with Claude"))))))

(ert-deftest actions/claude-on-a-selection ()
  "A selection: explain it, add it (not the whole file)."
  (+test-actions--in "some code"
    (setq buffer-file-name (+test-tmp-file "a.el"))
    (set-mark 1) (goto-char 5) (activate-mark)
    (should (equal (+test-actions--labels (+my/context-actions-claude))
                   '("Explain selection with Claude" "Add selection to Claude prompt")))
    (setq buffer-file-name nil)))

(ert-deftest actions/claude-on-a-selection-outside-files ()
  (+test-actions--in "some code"
    (set-mark 1) (goto-char 5) (activate-mark)
    (should (equal (+test-actions--labels (+my/context-actions-claude))
                   '("Explain selection with Claude" "Add selection to Claude prompt")))))

(ert-deftest actions/claude-on-an-error-in-a-selection ()
  (+test-actions--in "some code"
    (set-mark 1) (goto-char 5) (activate-mark)
    (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t)))
      (let ((actions (+my/context-actions-claude)))
        (should (equal (+test-actions--labels actions)
                       '("Fix error with Claude" "Explain error with Claude"
                         "Explain selection with Claude" "Add selection to Claude prompt")))
        (should (seq-every-p (lambda (a) (equal (car a) "Claude")) actions))))))

(ert-deftest actions/claude-on-an-evil-visual-selection ()
  "Visual state (M-RET is bound there): the selection, the character under
the cursor included."
  (+test-actions--in "some code here"
    (evil-local-mode 1)
    (goto-char 6)
    (evil-visual-char)
    (goto-char 9)
    (evil-visual-refresh)
    ;; As M-RET runs: evil expands the region to the selection first.
    (evil-visual-pre-command #'+my/context-actions)
    (let ((actions (+my/context-actions-claude))
          seen)
      (should (equal (+test-actions--labels actions)
                     '("Explain selection with Claude" "Add selection to Claude prompt")))
      (evil-normal-state)
      (cl-letf (((symbol-function 'agent-shell-send-region)
                 (lambda (&rest _)
                   (setq seen (buffer-substring (region-beginning) (region-end))))))
        (+test-actions--run actions "Add selection to Claude prompt"))
      (should (equal seen "code")))))

(ert-deftest actions/claude-inactive-mark-is-no-selection ()
  (+test-actions--in "some code"
    (set-mark 1) (goto-char 5) (deactivate-mark)
    (should-not (+my/context-actions-claude))))

(ert-deftest actions/claude-fix-error-sends-it ()
  (+test-actions--in "code"
    (+test-actions--with-claude
      (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t))
                ((symbol-function 'agent-shell--get-error-context)
                 (lambda () "a.el:1:1: error: void-function foo")))
        (+test-actions--run (+my/context-actions-claude) "Fix error with Claude")
        (should (equal (plist-get (car sent) :text)
                       "Fix this error:\n\na.el:1:1: error: void-function foo"))
        (should (eq (plist-get (car sent) :submit) t))))))

(ert-deftest actions/claude-explain-error-changes-nothing ()
  (+test-actions--in "code"
    (+test-actions--with-claude
      (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t))
                ((symbol-function 'agent-shell--get-error-context) (lambda () "E")))
        (+test-actions--run (+my/context-actions-claude) "Explain error with Claude")
        (should (equal (plist-get (car sent) :text)
                       "Explain this error and how to fix it. Don't change any files.\n\nE"))))))

(ert-deftest actions/claude-error-gone-nothing-to-send ()
  "The error went away before the action ran: nothing sent."
  (+test-actions--in "code"
    (+test-actions--with-claude
      (cl-letf (((symbol-function '+my/context-actions--error-at-point-p) (lambda () t))
                ((symbol-function 'agent-shell--get-error-context) (lambda () nil)))
        (should-error (+test-actions--run (+my/context-actions-claude) "Fix error with Claude")
                      :type 'user-error)
        (should-not sent)))))

(ert-deftest actions/claude-real-flymake-error ()
  "agent-shell's own error context, from flymake's diagnostic at point."
  (+test-actions--in "good bad good"
    (setq-local flymake-diagnostic-functions
                (list (lambda (report &rest _)
                        (funcall report (list (flymake-make-diagnostic
                                               (current-buffer) 6 9 :error "bad word here"))))))
    (flymake-mode 1)
    (flymake-start)
    (goto-char 7)
    (+test-actions--with-claude
      (+test-actions--run (+my/context-actions-claude) "Fix error with Claude")
      (let ((text (plist-get (car sent) :text)))
        (should (string-prefix-p "Fix this error:\n\n" text))
        (should (string-match-p "bad word here" text))))
    (flymake-mode -1)))

(ert-deftest actions/claude-explain-selection ()
  "The selection, as agent-shell sends one (its file:line link and the code),
though it was lost when the menu closed; the selection is deactivated."
  (+test-with-reset
    (let* ((transient-mark-mode t)
           (file (+test-file "claude-project/src/app.el" "(defun one ()\n  1)\n(defun two ()\n  2)\n"))
           (buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (switch-to-buffer buffer)
        (goto-char (point-min))
        (forward-line 2)
        (set-mark (point))
        (goto-char (point-max))
        (activate-mark)
        (+test-actions--with-claude
          (let ((actions (+my/context-actions-claude)))
            (deactivate-mark)
            (goto-char (point-min))
            (+test-actions--run actions "Explain selection with Claude")
            (let ((text (substring-no-properties (plist-get (car sent) :text))))
              (should (string-prefix-p "Explain this code. Don't change any files.\n\n" text))
              (should (string-match-p (regexp-quote "src/app.el:3-4") text))
              (should-not (string-match-p (regexp-quote cwd) text)) ; relative to the project
              (should (string-match-p "(defun two ()" text))
              (should-not (string-match-p "(defun one" text)))
            (should-not (region-active-p))
            (should (= (point) (point-min))))))
      (kill-buffer buffer))))

(ert-deftest actions/claude-add-selection ()
  "Into the prompt (agent-shell-send-region), the selection as when the menu
opened."
  (+test-actions--in "some code here"
    (set-mark 6) (goto-char 10) (activate-mark)
    (let ((actions (+my/context-actions-claude))
          seen)
      (deactivate-mark)
      (cl-letf (((symbol-function 'agent-shell-send-region)
                 (lambda (&rest _)
                   (setq seen (and (region-active-p)
                                   (buffer-substring (region-beginning) (region-end)))))))
        (+test-actions--run actions "Add selection to Claude prompt"))
      (should (equal seen "code")))))

(ert-deftest actions/claude-add-file ()
  (+test-actions--in "code"
    (setq buffer-file-name (+test-tmp-file "a.el"))
    (let (called)
      (cl-letf (((symbol-function 'agent-shell-send-file)
                 (lambda (&rest _) (setq called (current-buffer)))))
        (+test-actions--run (+my/context-actions-claude) "Add file to Claude prompt"))
      (should (eq called (current-buffer))))
    (setq buffer-file-name nil)))

;; ====== THE MENU ======

(ert-deftest actions/collect-in-provider-order ()
  (let ((+my/context-action-providers
         (list (lambda () (list (list "B" "b1" #'ignore) (list "B" "b2" #'ignore)))
               (lambda () nil)
               (lambda () (list (list "A" "a1" #'ignore))))))
    (should (equal (mapcar (lambda (a) (nth 1 a)) (+my/context-actions--collect))
                   '("b1" "b2" "a1")))))

(ert-deftest actions/collect-leaves-providers-lists-alone ()
  "Providers may return lists they keep (constants): joining them doesn't
change those."
  (let* ((first (list (list "A" "a" #'ignore)))
         (second (list (list "B" "b" #'ignore)))
         (+my/context-action-providers (list (lambda () first) (lambda () second))))
    (should (= (length (+my/context-actions--collect)) 2))
    (should (= (length (+my/context-actions--collect)) 2))
    (should (equal first (list (list "A" "a" #'ignore))))
    (should (= (length first) 1))))

(ert-deftest actions/collect-none ()
  (let ((+my/context-action-providers (list #'ignore #'ignore)))
    (should-not (+my/context-actions--collect)))
  (let ((+my/context-action-providers nil))
    (should-not (+my/context-actions--collect))))

(ert-deftest actions/added-providers ()
  "A provider added as the comments say (at the end) comes last; one added in
front (PDFs' provider, config/pdf.el) first."
  (let ((+my/context-action-providers (list (lambda () (list (list "Mine" "m" #'ignore))))))
    (add-to-list '+my/context-action-providers (lambda () (list (list "Last" "l" #'ignore))) t)
    (add-to-list '+my/context-action-providers (lambda () (list (list "First" "f" #'ignore))))
    (should (equal (mapcar #'car (+my/context-actions--collect)) '("First" "Mine" "Last")))))

(ert-deftest actions/menu-none-here ()
  (let ((+my/context-action-providers (list #'ignore)))
    (let ((err (should-error (+my/context-actions) :type 'user-error)))
      (should (equal (cadr err) "No actions here")))))

(ert-deftest actions/menu-none-in-a-plain-buffer ()
  "The real providers, nothing at point: the user is told."
  (+test-actions--in "nothing here"
    (should-error (+my/context-actions) :type 'user-error)))

(ert-deftest actions/menu-runs-the-choice ()
  (let* ((ran nil)
         (+my/context-action-providers
          (list (lambda () (list (list "Spelling" "Change to \"hello\"" (lambda () (push 'hello ran)))
                                 (list "Spelling" "Add \"helo\" to dictionary" (lambda () (push 'add ran)))))
                (lambda () (list (list "Claude" "Fix error with Claude" (lambda () (push 'fix ran))))))))
    (+test-actions--menu (lambda (candidates) (nth 2 candidates))
      (+my/context-actions)
      (should (equal ran '(fix)))
      (should (equal (nth 0 menu) "Action: "))
      (should (eq (nth 3 menu) t)))))                ; only its actions

(ert-deftest actions/menu-in-provider-order ()
  "Candidates as the providers listed them, never sorted (by length, history...)."
  (let ((+my/context-action-providers
         (list (lambda () (list (list "Spelling" "Zzz long label" #'ignore)
                                (list "Spelling" "a" #'ignore)))
               (lambda () (list (list "Code actions" "Middle" #'ignore))))))
    (+test-actions--menu (lambda (candidates) (car candidates))
      (+my/context-actions)
      (should (equal (all-completions "" (nth 1 menu)) '("Zzz long label" "a" "Middle")))
      (let ((metadata (+test-actions--metadata (nth 1 menu))))
        (should (eq (alist-get 'display-sort-function metadata) #'identity))
        (should (eq (alist-get 'cycle-sort-function metadata) #'identity))))))

(ert-deftest actions/menu-groups ()
  "Grouped by provider (vertico shows the group titles): the group function
names a candidate's group, and leaves its text as is."
  (let ((+my/context-action-providers
         (list (lambda () (list (list "Spelling" "Add \"helo\" to dictionary" #'ignore)))
               (lambda () (list (list "Code actions" "Extract method" #'ignore)
                                (list "Claude" "Fix error with Claude" #'ignore))))))
    (+test-actions--menu (lambda (candidates) (car candidates))
      (+my/context-actions)
      (let* ((collection (nth 1 menu))
             (group (alist-get 'group-function (+test-actions--metadata collection)))
             (candidates (all-completions "" collection)))
        (should (functionp group))
        (should (equal (mapcar (lambda (c) (funcall group c nil)) candidates)
                       '("Spelling" "Code actions" "Claude")))
        (dolist (candidate candidates)
          (should (equal (funcall group candidate t) candidate)))))))

(ert-deftest actions/menu-completes-and-filters ()
  "The table completes as any: by prefix, testing a match."
  (let ((+my/context-action-providers
         (list (lambda () (list (list "Claude" "Fix error with Claude" #'ignore)
                                (list "Claude" "Explain error with Claude" #'ignore))))))
    (+test-actions--menu (lambda (candidates) (car candidates))
      (+my/context-actions)
      (let ((collection (nth 1 menu)))
        (should (equal (all-completions "Ex" collection) '("Explain error with Claude")))
        (should (test-completion "Fix error with Claude" collection))
        (should-not (test-completion "Fix" collection))
        (should (equal (try-completion "Fi" collection) "Fix error with Claude"))))))

(ert-deftest actions/menu-same-labels-made-unique ()
  "Two actions with the same label (e.g. two servers' \"Organize imports\"):
the second becomes \"<2>\", the third \"<3>\"; each runs its own."
  (let* ((ran nil)
         (+my/context-action-providers
          (list (lambda () (list (list "Code actions" "Organize imports" (lambda () (push 1 ran)))
                                 (list "Code actions" "Organize imports" (lambda () (push 2 ran)))))
                (lambda () (list (list "Other" "Organize imports" (lambda () (push 3 ran))))))))
    (+test-actions--menu (lambda (candidates) (nth 1 candidates))
      (+my/context-actions)
      (should (equal (all-completions "" (nth 1 menu))
                     '("Organize imports" "Organize imports <2>" "Organize imports <3>")))
      (should (equal ran '(2))))
    (setq ran nil)
    (+test-actions--menu (lambda (candidates) (nth 2 candidates))
      (+my/context-actions)
      (should (equal ran '(3))))))

(ert-deftest actions/menu-unique-past-existing-numbers ()
  "A label that already looks numbered doesn't make two the same."
  (let ((+my/context-action-providers
         (list (lambda () (list (list "G" "A <2>" #'ignore)
                                (list "G" "A" #'ignore)
                                (list "G" "A" #'ignore))))))
    (+test-actions--menu (lambda (candidates) (car candidates))
      (+my/context-actions)
      (let ((candidates (all-completions "" (nth 1 menu))))
        (should (equal candidates '("A <2>" "A" "A <3>")))
        (should (equal candidates (delete-dups (copy-sequence candidates))))))))

(ert-deftest actions/menu-real-providers ()
  "Spelling, code actions and Claude together, in that order, from a buffer
where all apply; the choice runs."
  (+test-actions--in "say helo now"
    (setq buffer-file-name (+test-tmp-file "a.txt"))
    (+test-actions--flag 5 9)
    (goto-char 6)
    (setq-local lsp-mode t)
    (let ((executed nil))
      (+test-actions--with-spell
        (cl-letf (((symbol-function 'lsp-code-actions-at-point)
                   (lambda (&rest _) (list (lsp-make-code-action :title "Fix typo"))))
                  ((symbol-function 'lsp-execute-code-action)
                   (lambda (action) (push action executed))))
          (+test-actions--menu (lambda (candidates) (car (member "Fix typo" candidates)))
            (+my/context-actions)
            (let* ((collection (nth 1 menu))
                   (group (alist-get 'group-function (+test-actions--metadata collection)))
                   (groups (delete-dups (mapcar (lambda (c) (funcall group c nil))
                                                (all-completions "" collection)))))
              (should (equal groups '("Spelling" "Code actions" "Claude"))))
            (should (= (length executed) 1))))))
    (setq buffer-file-name nil)))

(ert-deftest actions/menu-empty-answer ()
  "An empty answer picks nothing, without an error: in vertico, M-RET (Option+
Enter again) is `vertico-exit-input', which exits with the empty input (it
called nil: \"Symbol's function definition is void: nil\")."
  (let* ((ran nil)
         (+my/context-action-providers
          (list (lambda () (list (list "G" "Something" (lambda () (setq ran t))))))))
    (+test-actions--menu (lambda (_candidates) "")
      (should-not (+my/context-actions))
      (should-not ran))))

;;; test-actions.el ends here
