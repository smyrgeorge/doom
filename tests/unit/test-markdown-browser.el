;;; tests/unit/test-markdown-browser.el -*- lexical-binding: t; -*-
;; config/markdown/browser.el: SPC m P, the live preview's page in the
;; browser: written to a file of its own per Markdown buffer (the same file
;; again), its diagrams drawn as it loads (mermaid.js the downloaded copy,
;; else jsdelivr's), opened with `browse-url-of-file'; markdown-mode's
;; preview without pandoc; the files deleted as Emacs exits. No xwidgets
;; needed. pandoc runs for real (skipped without it).

(require 'json)
(require 'markdown-mode)
(+test-load "config/window" "config/webkit" "config/markdown" "config/mermaid")

(defconst +test-md-browser--doc
  (concat "# Diagrams\n\n"
          "```mermaid\nflowchart TD\n    A --> B\n```\n\n"
          "```mermaid\nsequenceDiagram\n    A->>B: hi\n```\n\n"
          "> [!NOTE]\n> A note.\n\n"
          "Math: $x^2$.\n\n"
          "```python\nprint(1)\n```\n\n"
          "![a picture](pic.png) and [a file](other.md).\n")
  "A Markdown with two blocks, an alert, math, code, an image and a link.")

(defmacro +test-md-browser (installed &rest body)
  "BODY in a Markdown file's buffer (`+test-md-browser--doc'), mermaid.js
INSTALLED or not, the pages written into the test's folder, `browsed' the
files opened in the browser."
  (declare (indent 1))
  `(let* ((temporary-file-directory (+test-tmp-file "md-browser/tmp/"))
          (file (+test-file "md-browser/doc/notes.md" +test-md-browser--doc))
          (browsed nil)
          (+md-browser--files nil)
          ;; GitHub's stylesheet, as Doom's markdown module sets it.
          (markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css")))
     (make-directory temporary-file-directory t)
     (cl-letf (((symbol-function 'browse-url-of-file) (lambda (f) (push f browsed)))
               ((symbol-function '+my/mermaid-js-installed-p) (lambda () ,installed)))
       (with-current-buffer (find-file-noselect file)
         (unwind-protect (progn ,@body)
           (set-buffer-modified-p nil)
           (kill-buffer))))))

(defun +test-md-browser--page (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun +test-md-browser--mermaid-url (page)
  (and (string-match "mdMermaid.setup({.*}, \\(\"[^\"]*\"\\));" page)
       (json-read-from-string (match-string 1 page))))

(ert-deftest markdown-browser/the-live-preview-s-page ()
  "The page the live preview shows: its blocks as <pre class=\"mermaid\">
drawn as it loads (mermaid.js the downloaded copy), the alert, math, code
for highlight.js, the file's folder its base; opened in the browser."
  (unless (executable-find "pandoc") (ert-skip "No pandoc"))
  (+test-md-browser t
    (call-interactively #'+my/markdown-preview-browser)
    (should (= (length browsed) 1))
    (let ((page (+test-md-browser--page (car browsed))))
      (should (string-suffix-p ".html" (car browsed)))
      (should (= (length (seq-filter (lambda (s) (string-match-p "class=\"mermaid\"" s))
                                     (split-string page "<pre")))
                 2))
      (should (string-search "window.mdMermaid" page))
      (should (equal (+test-md-browser--mermaid-url page) (+my/mermaid-js-url)))
      (should (string-search "addEventListener('DOMContentLoaded',function(){mdMermaid.draw();})" page))
      (should (string-search "markdown-alert" page))
      (should (string-search "<math" page))
      (should (string-search "highlight.min.js" page))
      (should (string-match-p "class=\"[^\"]*python" page))
      (should (string-search (format "<base href=\"%s\">" (+my/webkit-file-url (file-name-directory buffer-file-name)))
                             page))
      (should (string-search "src=\"pic.png\"" page))
      (should (string-search "href=\"other.md\"" page))
      ;; GitHub's look, the theme's.
      (should (string-search "github-markdown" page)))))

(ert-deftest markdown-browser/mermaid-js-from-the-cdn-until-downloaded ()
  (unless (executable-find "pandoc") (ert-skip "No pandoc"))
  (+test-md-browser nil
    (+my/markdown-preview-browser)
    (should (string-prefix-p "https://cdn.jsdelivr.net/npm/mermaid@"
                             (+test-md-browser--mermaid-url (+test-md-browser--page (car browsed)))))))

(ert-deftest markdown-browser/the-same-file-again-written-anew ()
  "Pressed again: the same file, the Markdown as it is now; another buffer's
its own; all deleted as Emacs exits."
  (unless (executable-find "pandoc") (ert-skip "No pandoc"))
  (+test-md-browser t
    (+my/markdown-preview-browser)
    (goto-char (point-max))
    (insert "\nAdded later.\n")
    (+my/markdown-preview-browser)
    (should (= (length browsed) 2))
    (should (equal (car browsed) (cadr browsed)))
    ;; Each word in a span of its own (pandoc's source positions).
    (should (string-search ">later<" (+test-md-browser--page (car browsed))))
    (let ((other (+test-file "md-browser/doc/other.md" "# Other\n")))
      (with-current-buffer (find-file-noselect other)
        (+my/markdown-preview-browser)
        (kill-buffer)))
    (should (= (length browsed) 3))
    (should-not (equal (car browsed) (cadr browsed)))
    (should (= (length +md-browser--files) 2))
    (should (memq #'+md-browser--delete-files-h kill-emacs-hook))
    (+md-browser--delete-files-h)
    (should-not (seq-some #'file-exists-p browsed))))

(ert-deftest markdown-browser/the-live-preview-s-page-unchanged ()
  "In Emacs, the page draws nothing as it loads (the update script does) and
takes the downloaded mermaid.js."
  (+test-md-browser nil
    (let ((page (+md-preview--page "<p>x</p>")))
      (should-not (string-search "DOMContentLoaded',function(){mdMermaid.draw" page))
      (should (equal (+test-md-browser--mermaid-url page) (+my/mermaid-js-url))))))

(ert-deftest markdown-browser/without-pandoc-markdown-mode-s-preview ()
  (let ((previewed 0))
    (cl-letf (((symbol-function 'executable-find) (lambda (name &rest _) (unless (equal name "pandoc") name)))
              ((symbol-function 'markdown-preview) (lambda (&rest _) (cl-incf previewed)))
              ((symbol-function 'browse-url-of-file) (lambda (&rest _) (error "Opened"))))
      (with-temp-buffer
        (markdown-mode)
        (+my/markdown-preview-browser)))
    (should (= previewed 1))))

(ert-deftest markdown-browser/no-webkit-needed ()
  "The page is written and opened without xwidgets (most Linux Emacsen)."
  (unless (executable-find "pandoc") (ert-skip "No pandoc"))
  (+test-md-browser t
    (let ((features (remq 'xwidget-internal features)))
      (+my/markdown-preview-browser))
    (should (= (length browsed) 1))))
