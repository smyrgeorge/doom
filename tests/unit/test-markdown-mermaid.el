;;; tests/unit/test-markdown-mermaid.el -*- lexical-binding: t; -*-
;; config/markdown/mermaid.el: ```mermaid blocks drawn in the Markdown
;; preview's page by mermaid.js (config/mermaid.el): its script and look in
;; the page, set up with the theme's config on the page's background; a draw
;; after each update (mermaid.js downloaded first, only for a Markdown with a
;; block); re-themed with the page; nothing without config/mermaid.el.
;; pandoc runs for real where a test needs its HTML (skipped without it).

(require 'xwidget)
(require 'json)
(require 'markdown-mode)
(+test-load "config/window" "config/webkit" "config/markdown" "config/mermaid")

;; doom-one's colours, as faces give them (no others).
(defmacro +test-md-mermaid (&rest body)
  "BODY with a dark theme's colours, mermaid.js there (not downloaded:
`ensured' counts the asks)."
  (declare (indent 0))
  `(let ((ensured 0)
         (+my/mermaid--json nil))
     (cl-letf (((symbol-function 'face-foreground)
                (lambda (face &rest _)
                  (alist-get face '((default . "#bbc2cf") (error . "#ff6c6b") (font-lock-keyword-face . "#51afef")))))
               ((symbol-function 'face-background)
                (lambda (face &rest _) (and (eq face 'default) "#282c34")))
               ((symbol-function 'frame-parameter)
                (let ((original (symbol-function 'frame-parameter)))
                  (lambda (frame parameter)
                    (if (eq parameter 'background-mode) 'dark (funcall original frame parameter)))))
               ((symbol-function '+my/mermaid-js-ensure) (lambda () (cl-incf ensured) t)))
       ,@body)))

(defconst +test-md-mermaid--doc
  "# Diagrams\n\n```mermaid\nflowchart TD\n    A --> B\n```\n\nText.\n"
  "A Markdown with a block.")

(ert-deftest markdown-mermaid/page-has-the-script-set-up ()
  (+test-md-mermaid
    (with-temp-buffer
      (insert +test-md-mermaid--doc)
      (let ((page (+md-preview--page "<p>x</p>")))
        (should (string-search "window.mmd" page))
        (should (string-search "window.mdMermaid" page))
        ;; The theme's config, on the page's background (GitHub's dark).
        (let ((setup (and (string-match "mdMermaid.setup(\\({.*}\\), \\(\"[^\"]*\"\\));" page)
                          (cons (match-string 1 page) (match-string 2 page)))))
          (should setup)
          (let ((config (json-parse-string (car setup) :object-type 'alist)))
            (should (equal (alist-get 'background (alist-get 'themeVariables config)) (+md-preview--page-color)))
            (should (equal (alist-get 'primaryBorderColor (alist-get 'themeVariables config)) "#51afef")))
          ;; mermaid.js's URL, loaded once a block shows up (not in the head).
          (should (equal (json-read-from-string (cdr setup)) (+my/mermaid-js-url)))
          (should-not (string-search "<script src=\"file://" page)))
        ;; An error in the theme's error colour.
        (should (string-search ".mermaid-error{color:#ff6c6b;" page))))))

(ert-deftest markdown-mermaid/drawn-after-each-update ()
  (+test-md-mermaid
    (with-temp-buffer
      (insert +test-md-mermaid--doc)
      (cl-letf (((symbol-function '+md-preview--fragment) (lambda () "<pre class=\"mermaid\"><code>x</code></pre>")))
        (let ((script (+md-preview--update-script)))
          (should (string-search "if (window.mdMermaid) mdMermaid.draw();" script))
          ;; After the content's swapped, before the scroll.
          (should (< (string-search "document.body.innerHTML=" script)
                     (string-search "mdMermaid.draw()" script)
                     (string-search "window.scrollTo" script)))))
      (should (= ensured 1)))))

(ert-deftest markdown-mermaid/no-block-no-mermaid-js ()
  "A Markdown without a block: nothing drawn, mermaid.js not downloaded."
  (+test-md-mermaid
    (with-temp-buffer
      (insert "# Plain\n\n```python\nprint(1)\n```\n\nThe word mermaid.\n")
      (should (equal (+md-preview--mermaid-draw-script) ""))
      (should (= ensured 0)))
    ;; ~~~ fences and indented ones count.
    (with-temp-buffer
      (insert "- item\n\n  ~~~ mermaid\n  flowchart TD\n  ~~~\n")
      (should (string-search "mdMermaid.draw()" (+md-preview--mermaid-draw-script))))))

(ert-deftest markdown-mermaid/without-mermaid-js-blocks-stay-code ()
  (+test-md-mermaid
    (cl-letf (((symbol-function '+my/mermaid-js-ensure) #'ignore))
      (with-temp-buffer
        (insert +test-md-mermaid--doc)
        (should (equal (+md-preview--mermaid-draw-script) ""))))))

(ert-deftest markdown-mermaid/re-themed-with-the-page ()
  (+test-md-mermaid
    (let ((script (+md-preview--theme-script)))
      (should (string-match-p "mdMermaid.setup({.*\"background\":\"#0d1117\".*}); mdMermaid.redraw();" script)))))

(ert-deftest markdown-mermaid/highlight-js-leaves-diagrams ()
  (should (string-search "pre:not(.mermaid) > code" +md-preview--highlight-js)))

(ert-deftest markdown-mermaid/nothing-without-config-mermaid ()
  "config/markdown.el without config/mermaid.el: the page as it was."
  (cl-letf (((symbol-function '+md-preview--mermaid-p) #'ignore))
    (with-temp-buffer
      (insert +test-md-mermaid--doc)
      (should (equal (+md-preview--mermaid-head) ""))
      (should (equal (+md-preview--mermaid-draw-script) ""))
      (should (equal (+md-preview--mermaid-theme-script) ""))
      (should-not (string-search "mdMermaid" (+md-preview--page "<p>x</p>"))))))

(ert-deftest markdown-mermaid/pandoc-writes-the-block-as-the-script-reads-it ()
  "pandoc's HTML for a block: <pre class=\"mermaid\" data-pos=...><code>, its
source as it is (the script draws it, the scroll finds its line)."
  (unless (executable-find "pandoc") (ert-skip "No pandoc"))
  (let ((temporary-file-directory (+test-tmp-file "pandoc/")))
    (with-temp-buffer
      (insert +test-md-mermaid--doc)
      (let ((html (+md-preview--fragment)))
        (should (string-match-p "<pre[^>]*class=\"mermaid\"" html))
        (should (string-match-p "<pre[^>]*data-pos=\"3:1" html))
        (should (string-search "<code>flowchart TD\n    A --&gt; B</code>" html))))))
