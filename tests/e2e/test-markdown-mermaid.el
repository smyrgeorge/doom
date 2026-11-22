;;; tests/e2e/test-markdown-mermaid.el -*- lexical-binding: t; -*-
;; config/markdown/mermaid.el in a GUI Emacs: ```mermaid blocks in Markdown's
;; live preview, drawn by mermaid.js (Doom's, copied; skipped without it,
;; xwidgets or pandoc): a block fenced by four backticks; a wide diagram in
;; a narrow pane, readable, scrolled in its box; an edited one's versions not
;; kept. Drawing, redrawing and re-theming: tests/e2e/test-mermaid.el.
;; run.sh: slow (~20 s beside the others: started first).

(require 'markdown-mode)
;; The preview's stylesheets (Doom's markdown module sets GitHub's).
(setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css"))
(+test-load "config/childframe" "config/banner" "config/window" "config/webkit" "config/markdown"
            "config/mermaid")

;; mermaid.js: Doom's, copied into the temp data folder.
(defvar +test-mdm--js (+test-mermaid-js-dir))

;; ====== HELPERS ======

(defun +test-mdm--window (md)
  "MD's preview's window."
  (get-buffer-window (buffer-local-value '+md-preview--buffer md)))

(defun +test-mdm--js (md script)
  "SCRIPT's value (a string) in MD's preview's view."
  (let ((window (+test-mdm--window md)))
    (with-current-buffer (window-buffer window)
      (+test-js (+my/webkit-xwidget window) (format "String(%s)" script)))))

(defun +test-mdm--drawn (md count)
  "MD's preview, once its page shows COUNT diagrams drawn."
  (+test-wait-for
   (lambda ()
     (let ((window (+test-mdm--window md)))
       (and window
            (with-current-buffer (window-buffer window) (+my/webkit-xwidget window))
            (equal (+test-mdm--js md "document.querySelectorAll('div.mermaid-diagram svg').length")
                   (number-to-string count)))))
   20))

(defun +test-mdm--open (name markdown)
  "A Markdown file NAME of MARKDOWN, its preview on (SPC m p): its buffer."
  (let ((md (find-file (+test-file (concat "mdm/" name) markdown))))
    (markdown-mode)
    (let ((this-command '+my/markdown-preview-toggle))
      (+my/markdown-preview-toggle))
    md))

(defmacro +test-mdm (&rest body)
  "BODY with WebKit, pandoc and mermaid.js there, from one window; the
previews and files closed after."
  (declare (indent 0))
  `(progn
     (+test-needs-webkit)
     (unless (executable-find "pandoc") (ert-skip "No pandoc"))
     (unless +test-mdm--js
       (ert-skip "No mermaid.js in Doom's data folder (open a Mermaid preview once)"))
     (+test-with-reset
       (unwind-protect (progn ,@body)
         (dolist (buffer (buffer-list))
           (when (buffer-local-value '+md-preview-mode buffer)
             (with-current-buffer buffer (+md-preview-mode -1)))
           (when (buffer-file-name buffer)
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))))))

;; ====== FENCES ======

(ert-deftest e2e-markdown-mermaid/a-block-fenced-by-four-backticks-drawn ()
  "A Markdown whose only diagram is fenced by four backticks (a block that
may hold ``` lines): drawn, mermaid.js loaded for it."
  (+test-mdm
    (let ((md (+test-mdm--open "fence.md" "# Fence\n\n````mermaid\nflowchart LR\n    A[Four backticks] --> B\n````\n")))
      (should (+test-mdm--drawn md 1))
      ;; Its label, its rows joined: wider than mermaid's 120 px, it's wrapped
      ;; (Linux's 15 px DejaVu Sans Mono: 126 px), a row each word.
      (should (string-search "Four backticks" (+test-mdm--js md "[...document.querySelectorAll('div.mermaid-diagram svg g.node text')].map(t => [...t.querySelectorAll('.text-outer-tspan')].map(r => r.textContent.trim()).join(' ')).join('|')"))))))

;; ====== WIDE DIAGRAMS ======

(defconst +test-mdm--wide
  (concat "```mermaid\nflowchart LR\n"
          "    A[Write the code] --> B[Run the tests] --> C[Read the failures]"
          " --> D[Fix the config] --> E[Run them again] --> F[Commit the fix]\n```\n")
  "A flowchart much wider than a narrow pane.")

(defconst +test-mdm--narrow "```mermaid\nflowchart TD\n    A[Small] --> B[Diagram]\n```\n"
  "A diagram narrower than a narrow pane.")

(ert-deftest e2e-markdown-mermaid/a-wide-diagram-scrolls-in-its-box ()
  "A flowchart over 1000 px wide in a 40-column pane: shrunk to fit no more
than to four fifths of its natural size, its labels readable; scrolled
sideways in its own box, not the page. A narrow diagram: its natural size,
centred."
  (+test-mdm
    (let ((md (+test-mdm--open "wide.md" (concat "# Wide\n\n" +test-mdm--wide "\nBetween.\n\n" +test-mdm--narrow))))
      (should (+test-mdm--drawn md 2))
      (let ((window (+test-mdm--window md)))
        (window-resize window (- 40 (window-total-width window)) t)
        (should (= (window-total-width window) 40))
        ;; Its view resized.
        (should (+test-wait-for
                 (lambda () (<= (string-to-number (+test-mdm--js md "innerWidth"))
                                (+ (window-body-width window t) 2)))
                 3)))
      (let ((natural (string-to-number (+test-mdm--js md "document.querySelector('div.mermaid-diagram svg').viewBox.baseVal.width")))
            (drawn (string-to-number (+test-mdm--js md "document.querySelector('div.mermaid-diagram svg').getBoundingClientRect().width")))
            (label (string-to-number (+test-mdm--js md "Math.min.apply(null, [...document.querySelector('div.mermaid-diagram svg').querySelectorAll('.nodeLabel, text')].map(l => l.getBoundingClientRect().height).filter(h => h > 0))"))))
        (should (> natural 1000))
        (should (>= drawn (* 0.8 natural)))
        (should (>= label 10)))
      ;; The page doesn't scroll sideways; the diagram's box does.
      (should (<= (string-to-number (+test-mdm--js md "document.documentElement.scrollWidth"))
                  (string-to-number (+test-mdm--js md "innerWidth"))))
      (should (equal (+test-mdm--js md "(function(b){ return b.scrollWidth > b.clientWidth; })(document.querySelector('div.mermaid-diagram'))")
                     "true"))
      (should (equal (+test-mdm--js md "(function(b){ b.scrollLeft = 200; return b.scrollLeft > 0; })(document.querySelector('div.mermaid-diagram'))")
                     "true"))
      ;; The narrow one: its natural size, centred in its box.
      (let ((narrow "document.querySelectorAll('div.mermaid-diagram')[1]"))
        (should (< (abs (- (string-to-number (+test-mdm--js md (format "%s.querySelector('svg').getBoundingClientRect().width" narrow)))
                           (string-to-number (+test-mdm--js md (format "%s.querySelector('svg').viewBox.baseVal.width" narrow)))))
                   1))
        (should (< (abs (string-to-number
                         (+test-mdm--js md (format "(function(b){ var s=b.querySelector('svg').getBoundingClientRect(), r=b.getBoundingClientRect(); return (s.left - r.left) - (r.right - s.right); })(%s)" narrow))))
                   2))))))

;; ====== EDITED ======

(ert-deftest e2e-markdown-mermaid/an-edited-diagram-s-versions-forgotten ()
  "A block edited 50 times (each drawn): only the drawings of the blocks on
the page kept, the other block's still drawn from them."
  (+test-mdm
    (let ((md (+test-mdm--open "edited.md" (concat "# Edited\n\n```mermaid\nflowchart LR\n    A[Version 0] --> B\n```\n\n"
                                                   +test-mdm--narrow))))
      (should (+test-mdm--drawn md 2))
      (dotimes (i 50)
        (with-current-buffer md
          (goto-char (point-min))
          (re-search-forward "Version [0-9]+")
          (replace-match (format "Version %d" (1+ i)))
          (+md-preview--update md))
        (should (+test-wait-for
                 (lambda () (string-search (format "Version %d" (1+ i))
                                           (+test-mdm--js md "document.querySelector('div.mermaid-diagram svg') && document.querySelector('div.mermaid-diagram svg').textContent")))
                 5)))
      (should (<= (string-to-number (+test-mdm--js md "mdMermaid.drawn.size")) 2))
      (should (equal (+test-mdm--js md "document.querySelectorAll('div.mermaid-diagram svg').length") "2")))))

;; ====== IN THE BROWSER ======

(defvar +test-mdm--browser-page nil
  "The page SPC m P wrote, shown by `+test-mdm-browser-mode'.")

(define-derived-mode +test-mdm-browser-mode +my/webkit-mode "Browser"
  "SPC m P's page in WebKit, as a browser has it: no update script from
Emacs."
  (setq-local +my/webkit-url-function
              (lambda (_window) (+my/webkit-file-url +test-mdm--browser-page))))

(ert-deftest e2e-markdown-mermaid/drawn-in-the-browser-s-page ()
  "SPC m P's page (markdown/browser.el) loaded as a browser does, with
nothing from Emacs: its two blocks drawn as it loads, one with an error
shows Mermaid's message."
  (+test-mdm
    (let ((browsed nil))
      (cl-letf (((symbol-function 'browse-url-of-file) (lambda (file) (push file browsed))))
        (with-current-buffer (find-file (+test-file "mdm/browser.md"
                                                    (concat "# In the browser\n\n"
                                                            "```mermaid\nflowchart TD\n    A --> B\n```\n\n"
                                                            "```mermaid\nsequenceDiagram\n    A->>B: hi\n```\n\n"
                                                            "```mermaid\nflowchart TD\n    A --> \n```\n")))
          (markdown-mode)
          (+my/markdown-preview-browser)))
      (should (= (length browsed) 1))
      (setq +test-mdm--browser-page (car browsed))
      (let ((buffer (get-buffer-create "*test browser page*")))
        (switch-to-buffer buffer)
        (+test-mdm-browser-mode)
        (let ((count (lambda (selector)
                       (+test-js (+my/webkit-xwidget (selected-window))
                                 (format "String(document.querySelectorAll('%s').length)" selector)))))
          (should (+test-wait-for
                   (lambda ()
                     (and (+my/webkit-xwidget (selected-window))
                          (equal (funcall count "div.mermaid-diagram svg") "2")
                          (equal (funcall count "div.mermaid-diagram .mermaid-error") "1")))
                   20))
          (should (equal (funcall count "pre.mermaid") "0")))
        (kill-buffer buffer)))))
