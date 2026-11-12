;;; tests/unit/test-agent-shell-mermaid.el -*- lexical-binding: t; -*-
;; config/agent-shell/mermaid.el: ```mermaid blocks in Claude Code's replies
;; drawn as diagrams. A reply rendered as agent-shell renders it
;; (`agent-shell-markdown-replace-markup', its renderers' hook): a closed
;; block's source in its place, its Markdown kept (copying), the diagram
;; shown once the stand-in mmdc drew it; one streaming left as it is; an
;; error or no mmdc: the source and the message; a theme switch draws again;
;; resized as agent-shell's images; nothing in a terminal or without
;; config/mermaid.el; what Claude is told.

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)
(+test-load "config/agent-shell" "config/window" "config/webkit" "config/mermaid")
(require 'agent-shell)
(require 'mermaid-mode)                 ; autoloaded in Doom: blocks highlighted
(load (expand-file-name "../helper-mermaid" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defmacro +test-as-mermaid (&rest body)
  "BODY in a GUI (faked: images made, not drawn), the stand-in mmdc and a
stand-in theme, in a buffer shown in the selected window."
  (declare (indent 0))
  `(+test-mermaid--with-mmdc
     (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
               ((symbol-function 'image-type-available-p) (lambda (&rest _) t))
               ((symbol-function 'image-flush) #'ignore))
       (+test-mermaid--theme +test-mermaid--dark
         (with-current-buffer (get-buffer-create "*test agent-shell mermaid*")
           (let ((inhibit-read-only t)) (erase-buffer))
           (switch-to-buffer (current-buffer))
           (unwind-protect (progn ,@body)
             (kill-buffer)))))))

(defconst +test-as-mermaid--reply
  "Here:\n\n```mermaid\nflowchart TD\n    A --> B\n```\n\nDone.\n"
  "A reply with a diagram.")

(defun +test-as-mermaid--render (text)
  "TEXT appended, the buffer rendered as agent-shell renders a reply."
  (goto-char (point-max))
  (insert text)
  (agent-shell-markdown-replace-markup))

(defun +test-as-mermaid--region ()
  "The buffer's diagram: (START END . SOURCE), or nil."
  (car (+my/agent-shell-mermaid--regions)))

(defun +test-as-mermaid--display ()
  (when-let* ((region (+test-as-mermaid--region)))
    (get-text-property (car region) 'display)))

(defun +test-as-mermaid--drawn-p ()
  (eq (car-safe (+test-as-mermaid--display)) 'image))

(ert-deftest agent-shell-mermaid/registered ()
  (should (memq #'+my/agent-shell-mermaid-render agent-shell-markdown-render-functions))
  (should (memq #'+my/agent-shell-mermaid-theme-h +my/mermaid-theme-hook))
  (should (memq #'+my/agent-shell-mermaid-context +my/agent-shell-claude-context-functions)))

(ert-deftest agent-shell-mermaid/a-closed-block-drawn ()
  (+test-as-mermaid
    (+test-as-mermaid--render +test-as-mermaid--reply)
    (pcase-let ((`(,start ,end . ,source) (+test-as-mermaid--region)))
      ;; Its source in its place, highlighted, frozen; the fences gone.
      (should (equal source "flowchart TD\n    A --> B"))
      (should (equal (buffer-substring-no-properties start end) "flowchart TD\n    A --> B"))
      (should (memq 'font-lock-keyword-face (ensure-list (get-text-property start 'face))))
      (should (get-text-property start 'agent-shell-markdown-frozen))
      (should-not (string-search "```" (buffer-string)))
      ;; Its Markdown kept: copied, the reply as it came.
      (should (equal (agent-shell-markdown-reconstruct (point-min) (point-max)) +test-as-mermaid--reply)))
    ;; Drawn in the background, then shown over its source.
    (should-not (+test-as-mermaid--drawn-p))
    (should (+test-mermaid--wait #'+test-as-mermaid--drawn-p))
    (let ((image (+test-as-mermaid--display)))
      (should (file-in-directory-p (image-property image :file) +my/mermaid-cache-directory))
      (should (string-search "flowchart TD" (+test-mermaid--text (image-property image :file))))
      (should (integerp (image-property image :max-width))))
    ;; The line after it isn't drawn over.
    (pcase-let ((`(,_ ,end . ,_) (+test-as-mermaid--region)))
      (should (eq (char-after end) ?\n))
      (should-not (get-text-property end 'display)))
    (should (string-search "Done." (buffer-string)))))

(ert-deftest agent-shell-mermaid/streaming-left-until-closed ()
  (+test-as-mermaid
    (+test-as-mermaid--render "Here:\n\n```mermaid\nflowchart TD\n")
    (should-not (+test-as-mermaid--region))
    (should (string-search "```mermaid\nflowchart TD" (buffer-string)))
    (+test-as-mermaid--render "    A --> B\n```\n")
    (should (equal (cddr (+test-as-mermaid--region)) "flowchart TD\n    A --> B"))
    (should (+test-mermaid--wait #'+test-as-mermaid--drawn-p))))

(ert-deftest agent-shell-mermaid/drawn-already-at-once ()
  (+test-as-mermaid
    (+test-as-mermaid--render +test-as-mermaid--reply)
    (should (+test-mermaid--wait #'+test-as-mermaid--drawn-p))
    (let ((inhibit-read-only t)) (erase-buffer))
    (+test-as-mermaid--render +test-as-mermaid--reply)
    ;; Its drawing from the cache, once agent-shell's passes are done.
    (accept-process-output nil 0.05)
    (should (+test-as-mermaid--drawn-p))
    (should (= (length (+test-mermaid--runs mmdc)) 1))))

(ert-deftest agent-shell-mermaid/an-error-under-the-source ()
  (+test-as-mermaid
    (+test-as-mermaid--render "```mermaid\nflowchart TD\n    A --> ERROR\n```\n")
    (should (+test-mermaid--wait #'+test-as-mermaid--display))
    (let ((display (+test-as-mermaid--display)))
      (should (stringp display))
      (should (string-prefix-p "flowchart TD\n    A --> ERROR\nParse error on line 2:" display))
      (should (eq (get-text-property (string-search "Parse" display) 'face display) 'error)))))

(ert-deftest agent-shell-mermaid/without-mmdc-what-to-install ()
  (+test-as-mermaid
    (let ((+my/mermaid-mmdc (expand-file-name "no-such-mmdc" +test-tmp)))
      (+test-as-mermaid--render +test-as-mermaid--reply)
      (should (+test-mermaid--wait #'+test-as-mermaid--display))
      (should (string-search "npm install -g @mermaid-js/mermaid-cli" (+test-as-mermaid--display))))))

(ert-deftest agent-shell-mermaid/a-theme-switch-draws-again ()
  (+test-as-mermaid
    (+test-as-mermaid--render +test-as-mermaid--reply)
    (should (+test-mermaid--wait #'+test-as-mermaid--drawn-p))
    (let ((dark (image-property (+test-as-mermaid--display) :file)))
      (+test-mermaid--theme +test-mermaid--light
        (run-hooks '+my/mermaid-theme-hook)
        (should (+test-mermaid--wait
                 (lambda () (not (equal (image-property (+test-as-mermaid--display) :file) dark)))))
        (should (string-search "\"darkMode\":false"
                               (+test-mermaid--text (image-property (+test-as-mermaid--display) :file))))))))

(ert-deftest agent-shell-mermaid/resized-as-images-are ()
  (+test-as-mermaid
    (+test-as-mermaid--render +test-as-mermaid--reply)
    (should (+test-mermaid--wait #'+test-as-mermaid--drawn-p))
    (pcase-let ((`(,start . ,_) (+test-as-mermaid--region)))
      (should (eq (get-text-property start 'agent-shell-markdown-image-width-ratio) 'default))
      (let ((agent-shell-markdown-image-max-width 0.5))
        (agent-shell-markdown-rerender-images :force t)
        (should (= (image-property (get-text-property start 'display) :max-width)
                   (round (* 0.5 (window-body-width nil t)))))))))

(ert-deftest agent-shell-mermaid/a-terminal-or-no-mermaid-a-code-block ()
  (+test-as-mermaid
    (cl-letf (((symbol-function 'display-graphic-p) #'ignore))
      (+test-as-mermaid--render +test-as-mermaid--reply))
    (should-not (+test-as-mermaid--region))
    ;; agent-shell's own code block.
    (should (text-property-any (point-min) (point-max) 'agent-shell-markdown-source-block-body t)))
  (+test-as-mermaid
    (cl-letf (((symbol-function '+my/agent-shell-mermaid-p) #'ignore))
      (+test-as-mermaid--render +test-as-mermaid--reply))
    (should-not (+test-as-mermaid--region))))

(ert-deftest agent-shell-mermaid/claude-is-told ()
  (should (string-search "```mermaid" (+my/agent-shell-mermaid-context)))
  (should (string-search "instead of rendering diagram code to an image" (+my/agent-shell-mermaid-context)))
  (cl-letf (((symbol-function 'fboundp)
             (let ((original (symbol-function 'fboundp)))
               (lambda (symbol) (and (not (eq symbol '+my/mermaid-render)) (funcall original symbol))))))
    (should-not (+my/agent-shell-mermaid-context))))
