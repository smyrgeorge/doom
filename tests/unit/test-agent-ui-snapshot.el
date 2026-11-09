;;; tests/unit/test-agent-ui-snapshot.el -*- lexical-binding: t; -*-
;; config/agent-ui/snapshot.el: elements in the conversation. A snapshot: the
;; element as an SVG (its text in its colours, a chart's own SVG nested) in
;; the agent's .agent-shell/images/, with a Markdown link for its reply; an
;; element into its session's prompt, as text.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-aush (&rest body)
  "BODY with a canvas of its own (`canvas', killed after), no window shown,
`dir' a temp folder."
  (declare (indent 0))
  `(let* ((agent-ui-default-canvas (make-temp-name "snapshot-"))
          (agent-ui-display-function #'ignore)
          (dir (file-name-as-directory (make-temp-file (+test-tmp-file "snap-") t)))
          (canvas (progn (agent-ui-show '(:id "first" :type "text" :text "x")) (agent-ui-canvas))))
     (unwind-protect (progn ,@body)
       (kill-buffer canvas))))

(defun +test-aush-read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

;; ====== AS SVG ======

(ert-deftest agent-ui-snapshot/text-as-svg ()
  (let* ((text (concat (propertize "Done" 'face 'agent-ui-success) " & "
                       (propertize "<b>" 'face 'bold) "\n" "second line"))
         (svg (agent-ui-snapshot-svg text (agent-ui-context :width 40 :char-width 8 :line-height 16))))
    (should (string-prefix-p "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" svg))
    ;; Each run at its column, escaped, bold where its face is.
    (should (string-match-p "<text x=\"8\" y=\"20\" fill=\"#[0-9a-fA-F]+\"[^>]*>Done</text>" svg))
    (should (string-match-p "<text x=\"48\" [^>]*>&amp;</text>" svg))
    (should (string-match-p "<text x=\"64\" [^>]*font-weight=\"bold\">&lt;b&gt;</text>" svg))
    (should (string-match-p "<text x=\"8\" y=\"36\" [^>]*>second</text><text x=\"64\" y=\"36\" [^>]*>line</text>" svg))
    ;; Wide as its longest line, two lines high, padded.
    (should (string-match-p "width=\"104\" height=\"48\"" svg))
    ;; It reads as an image.
    (should (create-image svg 'svg t))))

(ert-deftest agent-ui-snapshot/a-chart-nested ()
  (let* ((ctx (agent-ui-context :width 40 :graphic t :char-width 8 :line-height 16))
         (text (agent-ui-render '(:type "chart" :title "T" :values (1 3 2)) ctx))
         (svg (agent-ui-snapshot-svg text ctx)))
    (should (string-match-p ">T</text>" svg))
    ;; The chart's own SVG, under its title.
    (should (string-match-p "<svg x=\"8\" y=\"24\" width=\"320\"" svg))
    (should (string-match-p "<polyline" svg))))

;; A bar's blocks: rectangles (full ones joined), ░ faint, the rest text.
(ert-deftest agent-ui-snapshot/bars-as-rectangles ()
  (let ((svg (agent-ui-snapshot-svg "███▌░░  50%" (agent-ui-context :width 20 :char-width 8 :line-height 16))))
    (should (string-match-p "<rect x=\"8\" y=\"[0-9]+\" width=\"24\" height=\"11\"" svg))
    (should (string-match-p "<rect x=\"32\" [^>]*width=\"4.0\"" svg))
    (should (= 2 (cl-count ?\n (replace-regexp-in-string "fill-opacity=\"0.25\"" "\n" svg))))
    (should (string-match-p "<text x=\"72\" [^>]*>50%</text>" svg))
    (should-not (string-match-p "█" svg))))

;; An image element's: its file embedded, at its shown size.
(ert-deftest agent-ui-snapshot/an-image-embedded ()
  (let* ((file (expand-file-name "images/splash.svg" data-directory))
         (ctx (agent-ui-context :width 40 :graphic t :char-width 8 :line-height 16))
         (text (agent-ui-render (list :type "image" :file file :title "Splash") ctx)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'image-size) (lambda (&rest _) '(120 . 90))))
      (let ((svg (agent-ui-snapshot-svg text ctx)))
        (should (string-match-p ">Splash</text>" svg))
        (should (string-match-p "<g transform=\"translate(8 24)\"><image width=\"120\" height=\"90\" href=\"data:image/svg\\+xml;base64," svg))
        ;; Under its title: padding, its title, the image, padding (8 16 90 8).
        (should (string-match-p "height=\"122\"" svg))))
    ;; Where its size can't be had (a terminal): its line, not an error.
    (should (agent-ui-snapshot-svg text ctx))))

;; ====== A SNAPSHOT ======

(ert-deftest agent-ui-snapshot/saved-for-the-reply ()
  (+test-aush
    (agent-ui-show '(:id "build" :type "progress" :title "Build [main]" :value 3 :max 4))
    (let* ((snap (agent-ui-snapshot "build" :directory dir))
           (file (plist-get snap :file)))
      (should (string-prefix-p (expand-file-name ".agent-shell/images/agent-ui-build-" dir) file))
      (should (string-suffix-p ".svg" file))
      (should (string-match-p ">3/4</text><text x=\"[0-9]+\" y=\"[0-9]+\" [^>]*>75%</text>" (+test-aush-read file)))
      (should (equal (plist-get snap :markdown) (format "![Build [main)](%s)" file))))
    ;; Through the command line's way in: in the agent's directory.
    (let* ((agent-ui--request-cwd dir)
           (reply (agent-ui-do "snapshot" "build" nil canvas)))
      (should (eq (plist-get reply :ok) t))
      (should (file-exists-p (plist-get reply :file))))
    (should (string-match-p "no element \"nope\""
                            (agent-ui-error-message
                             (should-error (agent-ui-snapshot "nope" :directory dir) :type 'agent-ui-error))))))

;; ====== INTO THE PROMPT ======

(ert-deftest agent-ui-snapshot/an-element-into-the-prompt ()
  (+test-aush
    (agent-ui-show '(:id "tests" :type "table" :columns ("Test" "Result") :rows (("lexer" "passed"))))
    (should (eq (lookup-key agent-ui-canvas-mode-map "a") #'agent-ui-send-element))
    (should (eq (lookup-key (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal) "a")
                #'agent-ui-send-element))
    (let ((shell (generate-new-buffer "shell"))
          (inserted nil))
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-insert)
                     (lambda (&rest args) (push args inserted))))
            (with-current-buffer canvas
              (agent-ui--flush)
              (goto-char (point-min))
              (search-forward "lexer")
              ;; No session: said.
              (setq agent-ui--session-buffer nil)
              (should-error (agent-ui-send-element) :type 'user-error)
              (setq agent-ui--session-buffer shell)
              (agent-ui-send-element))
            (should (eq (plist-get (car inserted) :shell-buffer) shell))
            (should (equal (plist-get (car inserted) :text)
                           (concat "Agent UI element tests (table), as it's shown:\n```text\n"
                                   " Test  │ Result\n───────┼───────\n lexer │ passed\n```\n")))
            ;; Not on an element.
            (with-current-buffer canvas
              (goto-char (point-max))
              (should-error (agent-ui-send-element) :type 'user-error)))
        (kill-buffer shell)))))
