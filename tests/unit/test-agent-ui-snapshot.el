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
(ert-deftest agent-ui-snapshot/an-image-where-it-is-in-its-line ()
  ;; A chart's SVG after a border's text (a panel's line): nested at its
  ;; column, the text after it past its width; the line as high as it.
  (let* ((chart "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"32\"><rect/></svg>")
         (line (concat "│ " (propertize "chart" 'display (list 'image :type 'svg :data chart)) " │"))
         (svg (agent-ui-snapshot-svg (concat line "\nnext") (agent-ui-context :width 40 :char-width 8 :line-height 16))))
    (should (string-match-p "<svg x=\"24\" y=\"8\" xmlns" svg))
    (should-not (string-match-p ">chart</text>" svg))
    ;; The border after it in its column (column 8: its line at x 76), down
    ;; to the line's bottom (the image's): no gap to the next line.
    (should (string-match-p "M76.0 16.0L76.0 8.0M76.0 16.0L76.0 40.0" svg))
    (should (string-match-p "<text x=\"8\" y=\"52\" [^>]*>next</text>" svg))
    ;; A filler after an image (a panel's): in the image's last column, the
    ;; border right after (45 px: 6 columns, its line at x 60).
    (let ((svg (agent-ui-snapshot-svg
                (concat (propertize "i" 'display (list 'image :type 'svg :data "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"45\" height=\"16\"/>"))
                        (propertize " " 'display '(space :width (3))) "│")
                (agent-ui-context :width 40 :char-width 8 :line-height 16))))
      (should (string-match-p "<path d=\"M60.0 16.0L60.0 8.0" svg)))
    ;; Words held to their cells' width.
    (should (string-match-p "textLength=\"32\" lengthAdjust=\"spacingAndGlyphs\">next</text>" svg))))

(ert-deftest agent-ui-snapshot/box-drawing-as-lines ()
  ;; A table's borders: lines from each cell's centre to its sides, meeting
  ;; from line to line; none as text.
  (let ((svg (agent-ui-snapshot-svg "a│b\n─┼─\n╭╯" (agent-ui-context :width 40 :char-width 8 :line-height 16))))
    (should-not (string-match-p ">[│─┼╭╯]+</text>" svg))
    ;; │ in column 1 of line 1: x 20, from y 16 to 8 (the top) and 24.
    (should (string-match-p "<path d=\"M20.0 16.0L20.0 8.0M20.0 16.0L20.0 24.0\" stroke=\"#[0-9a-fA-F]+\" stroke-width=\"1\" fill=\"none\"/>" svg))
    ;; ┼ under it: all four sides, its vertical on the same x.
    (should (string-match-p "M20.0 32.0L20.0 24.0M20.0 32.0L20.0 40.0M20.0 32.0L16.0 32.0M20.0 32.0L24.0 32.0" svg))
    ;; ─ beside it: across its cell.
    (should (string-match-p "M28.0 32.0L24.0 32.0M28.0 32.0L32.0 32.0" svg))
    ;; ╭: a curve from its bottom to its right.
    (should (string-match-p "M12.0 56.0Q12.0 48.0 16.0 48.0" svg))))

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

;; A run on a colour of its own (a GUI bar's): a rectangle of it.
(ert-deftest agent-ui-snapshot/backgrounds-as-rectangles ()
  (let ((svg (agent-ui-snapshot-svg (concat (propertize "   " 'face '(:background "#51afef")) " 50%")
                                    (agent-ui-context :width 20 :char-width 8 :line-height 16))))
    (should (string-match-p "<rect x=\"8\" y=\"[0-9]+\" width=\"24\" height=\"11\" fill=\"#51afef\"/>" svg))
    (should (string-match-p ">50%</text>" svg))))

;; ====== A SNAPSHOT ======

(ert-deftest agent-ui-snapshot/saved-for-the-reply ()
  (+test-aush
    (agent-ui-show '(:id "build" :type "progress" :title "Build [main]" :value 3 :max 4))
    (let* ((snap (agent-ui-snapshot "build" :directory dir))
           (file (plist-get snap :file)))
      (should (string-prefix-p (expand-file-name ".agent-shell/images/agent-ui-build-" dir) file))
      (should (string-suffix-p ".svg" file))
      (should (string-match-p ">3/4</text><text x=\"[0-9]+\" y=\"[0-9]+\" [^>]*>75%</text>" (+test-aush-read file)))
      (should (equal (plist-get snap :markdown) (format "![Build [main)](%s)" file)))
      ;; Again within the second: another file, the first kept.
      (let ((again (plist-get (agent-ui-snapshot "build" :directory dir) :file)))
        (should-not (equal again file))
        (should (file-exists-p file))))
    ;; Through the command line's way in: in the agent's directory.
    (let* ((agent-ui--request-cwd dir)
           (reply (agent-ui-do "snapshot" "build" nil canvas)))
      (should (eq (plist-get reply :ok) t))
      (should (file-exists-p (plist-get reply :file))))
    (should (string-match-p "no element \"nope\""
                            (agent-ui-error-message
                             (should-error (agent-ui-snapshot "nope" :directory dir) :type 'agent-ui-error))))))

(ert-deftest agent-ui-snapshot/no-buttons-in-it ()
  "A snapshot is still: an element's actions, a table's row buttons, a
choice's note and Answer left out (they'd do nothing in an image); the
canvas keeps them."
  (+test-aush
    (agent-ui-show '(:id "t" :type "text" :text "2 failed"
                     :actions ((:label "Fix them" :prompt "Fix the 2 failing tests"))))
    (agent-ui-show '(:id "tab" :type "table" :columns ("Test" "Result") :rows (("lexer" "failed"))
                     :row-actions ((:label "Show" :prompt "Show me {Test}"))))
    (agent-ui-show '(:id "c" :type "choice" :question "Which fix?" :options ("Change the test" "Revert it")
                     :note t))
    (dolist (id '("t" "tab" "c"))
      (let ((svg (+test-aush-read (plist-get (agent-ui-snapshot id :directory dir) :file))))
        (should-not (string-match-p "⏵" svg))
        (should-not (string-match-p "Add a note" svg))))
    (let ((svg (+test-aush-read (plist-get (agent-ui-snapshot "tab" :directory dir) :file))))
      (should (string-match-p "lexer" svg)))
    (let ((svg (+test-aush-read (plist-get (agent-ui-snapshot "c" :directory dir) :file))))
      ;; A word a <text> each.
      (should (string-match-p ">fix\\?<" svg))
      (should (string-match-p ">Revert<" svg)))
    ;; On the canvas: there.
    (with-current-buffer canvas
      (agent-ui--flush)
      (dolist (button '("⏵ Fix them" "⏵ Show" "⏵ Answer" "Add a note"))
        (should (save-excursion (goto-char (point-min)) (search-forward button nil t)))))
    ;; Drawn for a still picture: none; else, as on the canvas.
    (let ((element '(:type "text" :text "x" :actions ((:label "Go" :prompt "go")))))
      (should-not (string-match-p "⏵" (agent-ui-render element (agent-ui-context :still t))))
      (should (string-match-p "⏵ Go" (agent-ui-render element (agent-ui-context)))))))

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

;; ====== LINKS ======

(ert-deftest agent-ui-snapshot/a-link-to-an-element ()
  (+test-aush
    (should (equal (agent-ui-link "Claude Agent @ doom" "lat")
                   "agent-ui://canvas/Claude%20Agent%20%40%20doom#lat"))
    (should (equal (agent-ui-link "a") "agent-ui://canvas/a"))
    ;; browse-url opens it.
    (should (equal (browse-url-select-handler "agent-ui://canvas/x#y") #'agent-ui-open-link))
    (agent-ui-show '(:id "b" :type "text" :text "second"))
    (let ((link (agent-ui-link agent-ui-default-canvas "b")))
      (save-window-excursion
        (delete-other-windows)
        (let ((agent-ui-display-function #'agent-ui-display-canvas)
              (other (selected-window)))
          (ignore other)
          (should (eq (agent-ui-open-link link) canvas))
          ;; Its pane shown, selected, the cursor on the element.
          (should (eq (window-buffer (selected-window)) canvas))
          (should (equal (get-text-property (point) 'agent-ui-id) "b"))
          (should (looking-at "second")))))
    ;; Its show's reply has it.
    (should (equal (plist-get (agent-ui-do "show" nil '(:id "c" :type "text" :text "x") canvas) :link)
                   (agent-ui-link agent-ui-default-canvas "c")))
    (should-error (agent-ui-open-link "agent-ui://canvas/no-such-canvas#x") :type 'user-error)))

(ert-deftest agent-ui-snapshot/agent-shell-draws-it-as-a-link ()
  ;; As the agent's reply has it: a link agent-shell opens with browse-url.
  (require 'agent-shell-markdown)
  (with-temp-buffer
    (insert "See [the graph](agent-ui://canvas/Claude%20Agent%20%40%20doom#lat).")
    (agent-shell-markdown-replace-markup :render-images nil :highlight-blocks t :complete t)
    (should (equal (buffer-string) "See the graph."))
    (goto-char (point-min))
    (search-forward "graph")
    (should (equal (agent-shell-markdown-link-url-at-point (1- (point)))
                   "agent-ui://canvas/Claude%20Agent%20%40%20doom#lat"))))

;; ====== TEXT IN A TERMINAL'S COLOURS ======

(ert-deftest agent-ui-snapshot/ansi-colours ()
  ;; #RRGGBB as it is (not as the selected frame would show it).
  (should (equal (agent-ui--ansi-rgb "#51afef") "81;175;239"))
  (cl-letf (((symbol-function 'agent-ui-snapshot--bold-p) (lambda (face) (eq face 'bold)))
            ((symbol-function 'agent-ui-snapshot--color)
             (lambda (face attribute fallback)
               (pcase (list face attribute)
                 ('(default :foreground) "#bbc2cf") ('(default :background) "#282c34")
                 (`(agent-ui-accent :foreground) "#51afef")
                 (`((:background "#98be65") :background) "#98be65")
                 (_ fallback)))))
    (let ((text (concat (propertize "T" 'face 'bold) "\n"
                        (propertize "██" 'face 'agent-ui-accent) " 12\n"
                        (propertize "  " 'face '(:background "#98be65")))))
      (should (equal (agent-ui-ansi text)
                     (concat "\e[1mT\e[0m\n"
                             "\e[38;2;81;175;239m██\e[0m 12\n"
                             "\e[48;2;152;190;101m  \e[0m")))))
  ;; Plain text: as it is.
  (should (equal (agent-ui-ansi "plain\nlines") "plain\nlines")))

(ert-deftest agent-ui-snapshot/render-ansi ()
  (+test-aush
    (let ((element '(:type "chart" :kind "bar" :labels ("a") :values (3) :title "T")))
      (let ((agent-ui--request-options '("ansi")))
        (should (string-match-p "\\`\e\\[1mT\e\\[0m\na  \e\\["
                                (plist-get (agent-ui-do "render" nil element canvas) :text))))
      ;; Without --ansi: plain, as before.
      (should-not (string-match-p "\e" (plist-get (agent-ui-do "render" nil element canvas) :text))))))

