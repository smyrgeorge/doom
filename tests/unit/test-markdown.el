;;; tests/unit/test-markdown.el -*- lexical-binding: t; -*-
;; config/markdown.el: the live Markdown preview in WebKit (on config/webkit.el):
;; pandoc's fragment (source lines kept), the page, its colours, updates as you
;; type, scrolling to the cursor's line, the preview's pane and mode (opened
;; beside the file, closed with it, its temp file deleted), links, the notice
;; offering it, marksman's false link warnings, keys.
;; Batch Emacs has no GUI: WebKit is faked (`+test-md--with-fakes') and the
;; live preview made to work (`+my/webkit-p' t) where a test needs it. pandoc
;; runs for real in the fragment's tests (skipped without it); elsewhere the
;; fragment is faked, as the Markdown's text. Notices (config/banner.el) are
;; recorded, links out go to `+test-browsed' (tests/helper.el).

(require 'xwidget)                      ; before faking its functions
(require 'json)
(require 'markdown-mode)
;; lsp-mode as Doom has it: built for plists, and Doom says so at startup.
(setenv "LSP_USE_PLISTS" "1")
(require 'lsp-mode)
(+test-load "config/window" "config/webkit" "config/markdown")

;; ====== FAKE WEBKIT ======

(cl-defstruct (+test-md--xw (:constructor +test-md--xw-new) (:copier nil))
  "A fake WebKit view."
  buffer props uri title killed)

;; macOS's light or dark setting (an NS Emacs's variable): let-bound below,
;; it must be special on Linux too, where Emacs doesn't define it.
(defvar ns-system-appearance)

(defvar +test-md--made nil "The fake views made, oldest first.")
(defvar +test-md--scripts nil "(XWIDGET SCRIPT CALLBACK) run, oldest first.")
(defvar +test-md--notices nil "(show ID TEXT ACTIONS BUFFER) or (close ID BUFFER), latest first.")

(defmacro +test-md--with-fakes (&rest body)
  "BODY with WebKit's functions faked, notices recorded."
  (declare (indent 0))
  `(let ((+test-md--made nil)
         (+test-md--scripts nil)
         (+test-md--notices nil))
     (cl-letf (((symbol-function 'make-xwidget)
                (lambda (_type _title _width _height &optional _arguments buffer _related)
                  (let ((xw (+test-md--xw-new :buffer buffer)))
                    (setq +test-md--made (append +test-md--made (list xw)))
                    xw)))
               ((symbol-function 'xwidget-put)
                (lambda (xw property value)
                  (setf (+test-md--xw-props xw) (plist-put (+test-md--xw-props xw) property value))
                  value))
               ((symbol-function 'xwidget-get)
                (lambda (xw property) (plist-get (+test-md--xw-props xw) property)))
               ((symbol-function 'xwidget-live-p) #'+test-md--xw-p)
               ((symbol-function 'kill-xwidget) (lambda (xw) (setf (+test-md--xw-killed xw) t)))
               ((symbol-function 'xwidget-buffer) #'+test-md--xw-buffer)
               ((symbol-function 'set-xwidget-buffer)
                (lambda (xw buffer) (setf (+test-md--xw-buffer xw) buffer)))
               ((symbol-function 'set-xwidget-query-on-exit-flag) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-uri)
                (lambda (xw uri) (setf (+test-md--xw-uri xw) uri)))
               ((symbol-function 'xwidget-webkit-uri) #'+test-md--xw-uri)
               ((symbol-function 'xwidget-webkit-title) #'+test-md--xw-title)
               ((symbol-function 'xwidget-webkit-execute-script)
                (lambda (xw script &optional callback)
                  (setq +test-md--scripts (append +test-md--scripts (list (list xw script callback))))))
               ((symbol-function 'xwidget-webkit-adjust-size-to-window) #'ignore)
               ((symbol-function 'xwidget-window-inside-pixel-width) (lambda (_window) 700))
               ((symbol-function 'xwidget-window-inside-pixel-height) (lambda (_window) 500))
               ((symbol-function 'xwidget-webkit-stop-loading) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-history) #'ignore)
               ((symbol-function 'xwidget-webkit-callback) #'ignore)
               ((symbol-function '+my/banner-show)
                (lambda (id text &rest args)
                  (push (list 'show id text (plist-get args :actions) (current-buffer)) +test-md--notices)))
               ((symbol-function '+my/banner-close)
                (lambda (&optional id) (push (list 'close id (current-buffer)) +test-md--notices))))
       ,@body)))

;; ====== TIMERS ======

(defun +test-md--timers (function)
  (seq-filter (lambda (timer) (eq (timer--function timer) function))
              (append timer-list timer-idle-list)))

(defun +test-md--fire (function)
  "Run the pending timers calling FUNCTION now, once; return how many."
  (let ((timers (+test-md--timers function)))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-md--cancel-timers ()
  (dolist (timer (append timer-list timer-idle-list))
    (let ((function (timer--function timer)))
      (when (and (symbolp function)
                 (string-match-p "\\`\\+\\(my/webkit\\|md-\\)" (symbol-name function)))
        (cancel-timer timer)))))

;; ====== A MARKDOWN FILE AND ITS PREVIEW ======

(defun +test-md--fragment ()
  "The fake pandoc: the buffer's text in a paragraph."
  (format "<p>%s</p>" (buffer-substring-no-properties (point-min) (point-max))))

(defmacro +test-md (&rest body)
  "BODY with WebKit faked, the live preview working (`+my/webkit-p' t, pandoc
faked), temp files in the test's folder, as from a command (new windows
would get focus: config/window.el); from one window on *scratch*, and again
after."
  (declare (indent 0))
  `(+test-md--with-fakes
     (let ((temporary-file-directory
            (file-name-as-directory (make-temp-file (expand-file-name "tmp" (+test-tmp-file "dirs/")) t)))
           (+my/webkit--watch-timer nil)
           (+my/webkit--tidy-timer nil)
           (+test-browsed nil)
           (+my/markdown-preview-notice t)
           (+my/focus-new-windows t)
           (this-command 'test))
       (cl-letf (((symbol-function '+my/webkit-p) (lambda () t))
                 ((symbol-function '+md-preview--fragment) #'+test-md--fragment))
         (unwind-protect
             (+test-with-reset
               (setq +test-md--made nil +test-md--scripts nil +test-md--notices nil)
               ,@body)
           (+test-md--cancel-timers))))))

(defun +test-md--file (name content)
  "A Markdown file NAME (in the temp folder) with CONTENT, visited in the
selected window, in markdown-mode; its buffer."
  (let ((buffer (find-file-noselect (+test-file (concat "md/" name) content))))
    (switch-to-buffer buffer)
    (unless (derived-mode-p 'markdown-mode) (markdown-mode))
    buffer))

(defun +test-md--redisplay ()
  "What redisplay would do: each window showing a WebKit page gets its view."
  (dolist (window (window-list nil 'nomini))
    (when (with-current-buffer (window-buffer window) (derived-mode-p '+my/webkit-mode))
      (+my/webkit--shown-h window)))
  (+test-md--fire #'+my/webkit--start))

(defun +test-md--open-preview (&optional buffer)
  "Turn BUFFER's (default: current) preview on, its views started; the preview's buffer."
  (with-current-buffer (or buffer (current-buffer))
    (+md-preview-mode 1)
    (+test-md--redisplay)
    +md-preview--buffer))

(defun +test-md--xws (preview)
  (with-current-buffer preview (+my/webkit-xwidgets)))

(defun +test-md--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun +test-md--needs-pandoc ()
  (unless (executable-find "pandoc") (ert-skip "No pandoc")))

(defun +test-md--needs-new-pandoc ()
  "Skip unless pandoc is 3.8 or newer: older ones (Debian's, Ubuntu's) write
other markup (a paragraph's lines on a <div> around it, a task's box,
GitHub's alerts as quotes), which the preview shows as well."
  (+test-md--needs-pandoc)
  (let ((version (+md-preview--pandoc-version)))
    (unless (and version (version<= "3.8" version))
      (ert-skip (format "pandoc %s writes older markup" version)))))

;; ====== PANDOC ======

(defun +test-md--pandoc (markdown)
  "MARKDOWN's fragment, by pandoc (its input's temp file in the test's folder)."
  (let ((temporary-file-directory (+test-tmp-file "pandoc/")))
    (with-temp-buffer
      (insert markdown)
      (+md-preview--fragment))))

(ert-deftest markdown/github-alerts-in-github-s-markup ()
  "> [!NOTE] and the others: GitHub's markup (github-markdown-css styles it: a
coloured bar, the kind's icon and title), its source lines kept, its text
escaped; a plain quote stays one."
  (+test-md--needs-new-pandoc)
  (should (file-exists-p +md-preview--alerts-filter))
  (let ((html (+test-md--pandoc (concat "> [!CAUTION]\n> Salt & pepper.\n\n"
                                        "> [!NOTE]\n> n\n\n> [!TIP]\n> t\n\n"
                                        "> [!IMPORTANT]\n> i\n\n> [!WARNING]\n> w\n\n"
                                        "> Just a quote.\n"))))
    (should (string-match-p "<div class=\"markdown-alert markdown-alert-caution\" data-pos=\"1:1-" html))
    (dolist (kind '("note" "tip" "important" "warning"))
      (should (string-match-p (format "<div class=\"markdown-alert markdown-alert-%s\"" kind) html)))
    (should (string-match-p "<p class=\"markdown-alert-title\"><svg class=\"octicon[^\"]*\"[^>]*><path d=\"M[^\"]+\"></path></svg>Caution</p>" html))
    (with-temp-buffer
      (insert html)
      (should (= (how-many "class=\"markdown-alert-title\"" (point-min) (point-max)) 5)))
    ;; Its text, as any paragraph's (escaped).
    (should (string-match-p "Salt" html))
    (should (string-match-p "&amp;" html))
    (should-not (string-match-p "<div class=\"title\">" html))
    (should (string-match-p "<blockquote data-pos=" html))))

(ert-deftest markdown/fragment-tags-elements-with-their-source-lines ()
  (+test-md--needs-new-pandoc)
  (let ((html (+test-md--pandoc "# Title\n\nPara one\nstill para\n\n- item\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")))
    (should (string-match-p "<h1 data-pos=\"1:1-[0-9:]+\" id=\"title\">" html))
    (should (string-match-p "<p data-pos=\"3:1-" html))
    (should (string-match-p "<ul data-pos=\"6:1-" html))
    (should (string-match-p "<table data-pos=\"" html))
    ;; Inline wrappers marked: the scroll script skips them.
    (should (string-match-p "data-wrapper=\"1\"" html))
    ;; A fragment, not a page.
    (should-not (string-match-p "<html\\|<body\\|<head" html))))

(ert-deftest markdown/fragment-of-the-buffer-as-it-is ()
  "Unsaved changes rendered: the buffer, not its file."
  (+test-md--needs-pandoc)
  (with-current-buffer (find-file-noselect (+test-file "md/unsaved.md" "# On disk\n"))
    (erase-buffer)
    (insert "# In the buffer\n")
    (let ((html (let ((temporary-file-directory (+test-tmp-file "pandoc/")))
                  (+md-preview--fragment))))
      (should (string-search "id=\"in-the-buffer\"" html))
      (should-not (string-search "disk" html)))
    (set-buffer-modified-p nil)
    (kill-buffer)))

(ert-deftest markdown/fragment-keeps-unicode ()
  (+test-md--needs-pandoc)
  (let ((html (+test-md--pandoc "# Héllo ü文 ✓\n\nΚαλημέρα\n")))
    (should (string-search ">Héllo</span>" html))
    (should (string-search ">ü文</span>" html))
    (should (string-search "Καλημέρα" html))))

(ert-deftest markdown/fragment-leaves-code-to-highlight-js ()
  (+test-md--needs-pandoc)
  (let ((html (+test-md--pandoc "```python\nprint(1)\n```\n")))
    (should (string-match-p "<pre class=\"python\" data-pos=\"1:1-[0-9:]+\"><code>print(1)</code></pre>" html))
    (should-not (string-search "sourceCode" html))))

(ert-deftest markdown/fragment-math-as-mathml ()
  (+test-md--needs-pandoc)
  (let ((html (+test-md--pandoc "Inline $x^2$ and\n\n$$\\int_0^1 x\\,dx$$\n")))
    (should (string-search "<math display=\"inline\"" html))
    (should (string-search "<math display=\"block\"" html))))

(ert-deftest markdown/fragment-is-gfm ()
  (+test-md--needs-pandoc)
  (let ((html (+test-md--pandoc "~~gone~~ https://example.com\n\n- [x] done\n")))
    (should (string-search "<del>" html))
    (should (string-search "<a href=\"https://example.com\"" html))
    (should (string-search "done" html))
    ;; A task, done (older pandoc: a checkbox).
    (let ((version (+md-preview--pandoc-version)))
      (when (version<= "3.8" version)
        (should (string-search "<li>☒ " html))))))

(ert-deftest markdown/pandoc-arguments-by-version ()
  "No highlighting of pandoc's own, math as MathML: the arguments each pandoc
takes."
  (dolist (case '(("3.13" "--syntax-highlighting=none") ("3.8" "--syntax-highlighting=none")
                  ("3.1.11.1" "--no-highlight" "--mathml") ("2.17.1.1" "--no-highlight" "--mathml")
                  (nil "--no-highlight" "--mathml")))
    (let ((+md-preview--pandoc-args nil))
      (cl-letf (((symbol-function '+md-preview--pandoc-version) (lambda () (car case))))
        (should (equal (+md-preview--version-args) (cdr case)))
        ;; Asked once.
        (cl-letf (((symbol-function '+md-preview--pandoc-version) (lambda () (error "Asked again"))))
          (should (equal (+md-preview--version-args) (cdr case))))))))

(ert-deftest markdown/pandoc-version-read ()
  (+test-md--needs-pandoc)
  (should (string-match-p "\\`[0-9]+\\.[0-9.]+\\'" (+md-preview--pandoc-version))))

(ert-deftest markdown/fragment-of-nothing ()
  (+test-md--needs-pandoc)
  (should (string-blank-p (+test-md--pandoc ""))))

;; ====== THE PAGE ======

(ert-deftest markdown/page ()
  (with-temp-buffer
    (rename-buffer "notes.md" t)
    (setq buffer-file-name "/tmp/docs/notes.md")
    (let* ((markdown-css-paths '("https://cdn.example/github-markdown.css"
                                 "https://cdn.example/highlightjs/github.min.css"))
           (page (+md-preview--page "<p data-pos=\"1:1-2:1\">Hi</p>")))
      (should (string-prefix-p "<!doctype html><html><head><meta charset='utf-8'>" page))
      (should (string-suffix-p "</head><body class='markdown-body'><p data-pos=\"1:1-2:1\">Hi</p></body></html>" page))
      (dolist (part (list "<meta name='color-scheme' content='light dark'>"
                          "<style>@media (prefers-color-scheme: dark){html{background:#0d1117}}</style>"
                          (format "<title>Preview: %s</title>" (buffer-name))
                          "<link rel='stylesheet' href='https://cdn.example/github-markdown.css'>"
                          ;; highlight.js's light or dark theme, as the system is.
                          "<link rel='stylesheet' media='(prefers-color-scheme: light)' href='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github.min.css'>"
                          "<link rel='stylesheet' media='(prefers-color-scheme: dark)' href='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github-dark.min.css'>"
                          "body.markdown-body{box-sizing:border-box;max-width:none;width:100%;margin:0;"
                          "<script src='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js'></script>"
                          +md-preview--anchors-js
                          (concat "document.addEventListener('DOMContentLoaded',function(){"
                                  +md-preview--highlight-js "});")))
        (should (string-search part page)))
      ;; The light-only highlight.js theme of Doom's paths left out.
      (should-not (string-search "cdn.example/highlightjs" page)))
    (setq buffer-file-name nil)))

(defun +test-md--base (page)
  "The folder PAGE's <base> says relative links are in."
  (should (string-match "<base href=\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\)>" page))
  (let* ((href (or (match-string 1 page) (match-string 2 page)))
         (url (url-generic-parse-url href)))
    (should (equal (url-type url) "file"))
    (should-not (url-target url))
    (+my/webkit-url-file href)))

(ert-deftest markdown/page-base-is-the-files-folder ()
  "Relative links and images: from the Markdown file's folder."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/docs/notes.md")
    (should (equal (+test-md--base (+md-preview--page "")) "/tmp/docs/"))
    (setq buffer-file-name nil)
    (let ((default-directory "/tmp/scratch/"))
      (should (equal (+test-md--base (+md-preview--page "")) "/tmp/scratch/")))))

(ert-deftest markdown/page-base-of-an-odd-folder ()
  "A folder named C# (or with a quote, a space, a %): still its folder."
  (with-temp-buffer
    (dolist (dir '("/tmp/C#/" "/tmp/it's here/" "/tmp/100%/ü/" "/tmp/a\"b/"))
      (setq buffer-file-name (concat dir "README.md"))
      (should (equal (+test-md--base (+md-preview--page "")) dir)))
    (setq buffer-file-name nil)))

(ert-deftest markdown/page-colour ()
  (should (equal (+md-preview--page-color 'light) "#ffffff"))
  (should (equal (+md-preview--page-color 'dark) "#0d1117"))
  ;; macOS's setting first, else the frame's.
  (let ((ns-system-appearance 'light))
    (should (equal (+md-preview--page-color) "#ffffff")))
  (let ((ns-system-appearance 'dark))
    (should (equal (+md-preview--page-color) "#0d1117")))
  (let ((ns-system-appearance nil))
    (cl-letf* ((frame-parameter-fn (symbol-function 'frame-parameter))
               (mode 'light)
               ((symbol-function 'frame-parameter)
                (lambda (frame parameter)
                  (if (eq parameter 'background-mode) mode (funcall frame-parameter-fn frame parameter)))))
      (should (equal (+md-preview--page-color) "#ffffff"))
      (setq mode 'dark)
      (should (equal (+md-preview--page-color) "#0d1117")))))

(ert-deftest markdown/update-script-swaps-the-content ()
  (with-temp-buffer
    (insert "line 1\nline 2\nline 3 \"quoted\" ü </script>\n")
    (goto-char (point-min))
    (forward-line 2)
    (cl-letf (((symbol-function '+md-preview--fragment) #'+test-md--fragment))
      (let ((script (+md-preview--update-script)))
        (should (string-match "\\`document\\.body\\.innerHTML=\\(\".*\"\\);" script))
        (should (equal (json-parse-string (match-string 1 script)) (+test-md--fragment)))
        ;; Highlighted again, then scrolled to the cursor's line.
        (should (string-search +md-preview--highlight-js script))
        (should (string-suffix-p (format +md-preview--scroll-js 3) script))))))

;; ====== THE PREVIEW ======

(ert-deftest markdown/preview-opens-beside-the-file ()
  (+test-md
    (let* ((md (+test-md--file "README.md" "# Read me\n"))
           (window (selected-window))
           (width (window-total-width window))
           (preview (with-current-buffer md (+md-preview-mode 1) +md-preview--buffer))
           (pane (get-buffer-window preview)))
      (should (equal (buffer-name preview) "Preview: README.md"))
      (should pane)
      ;; Right of the file, half its window's width; the cursor stays in it.
      (should (> (window-left-column pane) (window-left-column window)))
      (should (= (window-top-line pane) (window-top-line window)))
      (should (<= (abs (- (window-total-width pane) (/ width 2))) 1))
      (should (eq (selected-window) window))
      (should (eq (current-buffer) md))
      (with-current-buffer preview
        (should (eq major-mode '+md-preview-page-mode))
        (should (eq +md-preview--source md)))
      (with-current-buffer md
        (should +md-preview-mode)
        (should (string-match-p "\\`md-preview-.*\\.html\\'" (file-name-nondirectory +md-preview--file)))
        (should (string-prefix-p temporary-file-directory +md-preview--file))
        (should (file-exists-p +md-preview--file))
        (should (memq #'+md-preview--after-change-h after-change-functions))
        (should (memq #'+md-preview--post-command-h post-command-hook))
        (should (memq #'+md-preview--off-h kill-buffer-hook))
        (should (memq #'+md-preview--off-h change-major-mode-hook))))))

(ert-deftest markdown/new-windows-would-take-focus ()
  "Control for the test above: here, a command's new window is selected."
  (+test-md
    (let ((window (selected-window)))
      (display-buffer (+test-buffer "other") '(display-buffer-in-direction (direction . right)))
      (should-not (eq (selected-window) window)))))

(ert-deftest markdown/preview-page-is-the-markdown-as-it-is ()
  (+test-md
    (let* ((md (+test-md--file "page.md" "# Saved\n"))
           (file nil))
      (with-current-buffer md (insert "Typed "))       ; not saved
      (let* ((preview (+test-md--open-preview md))
             (xw (car (+test-md--xws preview))))
        (setq file (buffer-local-value '+md-preview--file md))
        (should (= (length +test-md--made) 1))
        (should (eq (+test-md--xw-buffer xw) preview))
        (should (equal (+test-md--xw-uri xw) (+my/webkit-file-url file)))
        (let ((html (+test-md--text file)))
          (should (string-search "<p>Typed # Saved\n</p>" html))
          (should (string-search "<title>Preview: page.md</title>" html)))
        ;; Its colour: the cover's, and around the views.
        (with-current-buffer preview
          (should (equal (+my/webkit--background) (+md-preview--page-color)))
          (should (member (list :background (+md-preview--page-color))
                          (alist-get 'default face-remapping-alist))))))))

(ert-deftest markdown/preview-follows-typing ()
  "Updates ≈0.3 s after typing stops, in each pane of the preview, without
reloading."
  (+test-md
    (let* ((md (+test-md--file "typing.md" "# Typing\n"))
           (preview (+test-md--open-preview md)))
      (+test-md--redisplay)
      (let ((pane (get-buffer-window preview)))
        (set-window-buffer (split-window pane nil 'below) preview))
      (+test-md--redisplay)
      (should (= (length (+test-md--xws preview)) 2))
      (setq +test-md--scripts nil)
      (with-current-buffer md
        (goto-char (point-max))
        (insert "More")
        (insert " text")
        (let ((timers (+test-md--timers #'+md-preview--update)))
          (should (= (length timers) 1))                 ; the last edit's
          (should (memq (car timers) timer-idle-list))
          (should (equal (timer--args (car timers)) (list md)))
          ;; 0.3 s of idleness.
          (should (< (abs (- (float-time (timer--time (car timers))) 0.3)) 0.01))))
      (should-not +test-md--scripts)                   ; not while typing
      (+test-md--fire #'+md-preview--update)
      (should (= (length +test-md--scripts) 2))
      (should (seq-set-equal-p (mapcar #'car +test-md--scripts) (+test-md--xws preview)))
      (dolist (run +test-md--scripts)
        (should (string-prefix-p "document.body.innerHTML=\"<p># Typing\\nMore text</p>\";" (cadr run)))))))

(ert-deftest markdown/preview-scrolls-to-the-cursors-line ()
  (+test-md
    (let* ((md (+test-md--file "scroll.md" "a\nb\nc\nd\ne\n"))
           (preview (+test-md--open-preview md)))
      (with-current-buffer md
        (goto-char (point-min))
        (forward-line 2)
        (setq +test-md--scripts nil)
        (+md-preview--post-command-h)
        (should (equal (mapcar #'cadr +test-md--scripts)
                       (list (concat (format +md-preview--scroll-js 3) "\n;void 0"))))
        ;; The same line: nothing.
        (+md-preview--post-command-h)
        (should (= (length +test-md--scripts) 1))
        (forward-line 2)
        (+md-preview--post-command-h)
        (should (equal (cadr (car (last +test-md--scripts)))
                       (concat (format +md-preview--scroll-js 5) "\n;void 0")))
        (should (eq (caar +test-md--scripts) (car (+test-md--xws preview))))))))

(ert-deftest markdown/preview-loaded-shows-the-markdown-as-it-is ()
  "Back from a link, WebKit loads the page's file as it was written: the
Markdown as it is now, at the cursor's line, in that view."
  (+test-md
    (let* ((md (+test-md--file "loaded.md" "one\ntwo\n"))
           (preview (+test-md--open-preview md))
           (pane (get-buffer-window preview)))
      (set-window-buffer (split-window pane nil 'below) preview)
      (+test-md--redisplay)
      (let ((xw (car (+test-md--xws preview))))
        (with-current-buffer preview
          (should (memq #'+md-preview--loaded +my/webkit-load-functions)))
        (with-current-buffer md (insert "new "))
        (setq +test-md--scripts nil)
        (let ((last-input-event (list 'xwidget-event 'load-changed xw "load-finished")))
          (+my/webkit--callback xw 'load-changed))
        (should (equal (mapcar #'car +test-md--scripts) (list xw)))
        (should (string-prefix-p "document.body.innerHTML=\"<p>new one\\ntwo\\n</p>\";"
                                 (cadr (car +test-md--scripts))))))))

(ert-deftest markdown/preview-off-closes-its-pane ()
  (+test-md
    (let* ((md (+test-md--file "off.md" "# Off\n"))
           (window (selected-window))
           (preview (+test-md--open-preview md))
           (file (buffer-local-value '+md-preview--file md)))
      (with-current-buffer md
        (insert "x")                                   ; an update pending
        (+md-preview-mode -1)
        (should-not +md-preview--buffer)
        (should-not +md-preview--file)
        (should-not +md-preview--line)
        (should-not (memq #'+md-preview--after-change-h after-change-functions))
        (should-not (memq #'+md-preview--post-command-h post-command-hook))
        (should-not (memq #'+md-preview--off-h kill-buffer-hook))
        (should-not (memq #'+md-preview--off-h change-major-mode-hook)))
      (should-not (buffer-live-p preview))
      (should-not (file-exists-p file))
      (should-not (+test-md--timers #'+md-preview--update))
      (should (equal (window-list) (list window)))
      (should (eq (window-buffer window) md))
      (should (seq-every-p #'+test-md--xw-killed +test-md--made)))))

(ert-deftest markdown/preview-toggled-by-spc-m-p ()
  (+test-md
    (let ((md (+test-md--file "toggle.md" "# Toggle\n")))
      (with-current-buffer md
        (call-interactively #'+my/markdown-preview-toggle)
        (should +md-preview-mode)
        (should (buffer-live-p +md-preview--buffer))
        (call-interactively #'+my/markdown-preview-toggle)
        (should-not +md-preview-mode)
        (should-not (get-buffer "Preview: toggle.md"))))))

(ert-deftest markdown/preview-falls-back-to-eww-in-a-terminal ()
  (+test-md
    (let ((md (+test-md--file "terminal.md" "# Terminal\n"))
          (toggled nil))
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
                ((symbol-function 'markdown-live-preview-mode)
                 (lambda (&optional arg) (push (list arg (current-buffer)) toggled))))
        (with-current-buffer md
          (+my/markdown-preview-toggle)))
      (should (equal toggled (list (list 'toggle md))))
      (should-not (buffer-local-value '+md-preview-mode md)))))

(ert-deftest markdown/live-p-needs-webkit-and-pandoc ()
  (+test-md
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "pandoc") "/usr/bin/pandoc"))))
      (should (+my/markdown-preview-live-p))
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
        (should-not (+my/markdown-preview-live-p))))
    (cl-letf (((symbol-function 'executable-find) #'ignore))
      (should-not (+my/markdown-preview-live-p))))
  ;; Batch: no GUI.
  (should-not (+my/markdown-preview-live-p)))

(ert-deftest markdown/closing-the-file-closes-the-preview ()
  (+test-md
    (let* ((md (+test-md--file "closing.md" "# Closing\n"))
           (preview (+test-md--open-preview md))
           (file (buffer-local-value '+md-preview--file md)))
      (kill-buffer md)
      (should-not (buffer-live-p preview))
      (should-not (file-exists-p file))
      (should (= (length (window-list)) 1)))))

(ert-deftest markdown/closing-the-preview-turns-it-off ()
  "q (or its tab's ✕) in the preview: the Markdown buffer's preview is off,
its temp file gone; SPC m p opens it again."
  (+test-md
    (let* ((md (+test-md--file "q.md" "# Q\n"))
           (preview (+test-md--open-preview md))
           (file (buffer-local-value '+md-preview--file md)))
      (with-selected-window (get-buffer-window preview)
        (should (eq (key-binding "q") #'kill-current-buffer))
        (kill-current-buffer))
      (should-not (buffer-live-p preview))
      (with-current-buffer md
        (should-not +md-preview-mode)
        (should-not +md-preview--buffer)
        (should-not (memq #'+md-preview--after-change-h after-change-functions)))
      (should-not (file-exists-p file))
      (should (buffer-live-p md))
      (with-current-buffer md
        (+md-preview-mode 1)
        (should (buffer-live-p +md-preview--buffer))))))

(ert-deftest markdown/preview-alone-in-its-frame-off ()
  "The preview's pane the frame's only window: it shows another buffer once
the preview is gone."
  (+test-md
    (let* ((md (+test-md--file "alone.md" "# Alone\n"))
           (preview (+test-md--open-preview md)))
      (select-window (get-buffer-window preview))
      (delete-other-windows)
      (with-current-buffer md (+md-preview-mode -1))
      (should-not (buffer-live-p preview))
      (should (= (length (window-list)) 1))
      (should (buffer-live-p (window-buffer (selected-window)))))))

(ert-deftest markdown/another-major-mode-closes-the-preview ()
  "The Markdown buffer's mode set again (`normal-mode', a revert): its preview
doesn't stay behind, unconnected, its temp file left."
  (+test-md
    (let* ((md (+test-md--file "remode.md" "# Remode\n"))
           (preview (+test-md--open-preview md))
           (file (buffer-local-value '+md-preview--file md)))
      (with-current-buffer md (markdown-mode))
      (should (or (and (buffer-local-value '+md-preview-mode md)
                       (eq (buffer-local-value '+md-preview--buffer md) preview)
                       (buffer-live-p preview))
                  (and (not (buffer-live-p preview))
                       (not (file-exists-p file))))))))

(ert-deftest markdown/two-files-two-previews ()
  (+test-md
    (let* ((a (+test-md--file "a.md" "# A\n"))
           (pa (+test-md--open-preview a))
           (b (progn (select-window (get-buffer-window a)) (+test-md--file "b.md" "# B\n")))
           (pb (+test-md--open-preview b)))
      (should-not (eq pa pb))
      (should (eq (buffer-local-value '+md-preview--source pa) a))
      (should (eq (buffer-local-value '+md-preview--source pb) b))
      (kill-buffer b)
      (should-not (buffer-live-p pb))
      (should (buffer-live-p pa)))))

;; ====== LINKS ======

(ert-deftest markdown/links-out-open-in-the-browser ()
  (+test-md
    (let* ((md (+test-md--file "links.md" "[x](https://example.com)\n"))
           (preview (+test-md--open-preview md)))
      (with-current-buffer preview
        (+md-preview--follow "https://example.com/a?b=c")
        (+md-preview--follow "mailto:me@example.com"))
      (should (equal +test-browsed '("mailto:me@example.com" "https://example.com/a?b=c"))))))

(ert-deftest markdown/link-to-a-file-opens-in-the-markdown-files-pane ()
  (+test-md
    (let* ((md (+test-md--file "from.md" "[to](odd dir/to ü #1.md)\n"))
           (window (get-buffer-window md))
           (target (file-truename (+test-file "md/odd dir/to ü #1.md" "# To\n")))
           (preview (+test-md--open-preview md))
           (pane (get-buffer-window preview)))
      (with-current-buffer preview
        (select-window pane)
        (+md-preview--follow (concat (+my/webkit-file-url target) "#install")))
      (should (eq (selected-window) window))
      (should (equal (buffer-file-name (window-buffer window)) target))
      (should (eq (window-buffer pane) preview))       ; the preview stays
      (should-not +test-browsed))))

(ert-deftest markdown/link-to-a-file-without-the-markdown-files-pane ()
  (+test-md
    (let* ((md (+test-md--file "hidden.md" "# Hidden\n"))
           (target (file-truename (+test-file "md/target.md" "# Target\n")))
           (preview (+test-md--open-preview md))
           (pane (get-buffer-window preview)))
      (select-window pane)
      (delete-other-windows)                            ; the file not shown
      (with-current-buffer preview
        (+md-preview--follow (+my/webkit-file-url target)))
      ;; Beside the preview.
      (should (equal (buffer-file-name (window-buffer (selected-window))) target))
      (should (eq (window-buffer pane) preview))
      (should (= (length (window-list)) 2)))))

(ert-deftest markdown/link-clicked-in-the-preview ()
  "WebKit following a link out of the page (to another Markdown file): it
opens in Emacs, WebKit stays on the page."
  (+test-md
    (let* ((md (+test-md--file "click.md" "[next](next.md)\n"))
           (window (get-buffer-window md))
           (next (file-truename (+test-file "md/next.md" "# Next\n")))
           (preview (+test-md--open-preview md))
           (xw (car (+test-md--xws preview))))
      (with-current-buffer preview
        (should (eq +my/webkit-link-function #'+md-preview--follow)))
      (setf (+test-md--xw-uri xw) (+my/webkit-file-url next))
      (let ((last-input-event (list 'xwidget-event 'load-changed xw "load-started")))
        (+my/webkit--callback xw 'load-changed))
      (should (equal (buffer-file-name (window-buffer window)) next))
      ;; A heading of the page itself (#install) isn't a link out.
      (should-not (+my/webkit--elsewhere-p xw (concat (xwidget-get xw 'home) "#install"))))))

;; ====== THE NOTICE ======

(ert-deftest markdown/notice-offers-the-preview ()
  (should (eq (default-value '+my/markdown-preview-notice) t))
  (should (memq #'+my/markdown-preview-notice-h markdown-mode-hook))
  (should (memq #'+my/markdown-preview-notice-h markdown-ts-mode-hook))
  (should-not (seq-filter (lambda (f) (and (symbolp f) (string-match-p "notice" (symbol-name f))))
                         (default-value '+md-preview-mode-hook)))
  (+test-md
    (let ((md (+test-md--file "notice.md" "# Notice\n")))
      (should (equal +test-md--notices
                     (list (list 'show 'markdown-preview
                                 "See this file rendered next to it, updated as you type (SPC m p)."
                                 '(("Open preview" . +my/markdown-preview-show))
                                 md)))))))

(ert-deftest markdown/notice-only-where-the-preview-works ()
  (+test-md
    (let ((+my/markdown-preview-notice nil))
      (+test-md--file "no-notice.md" "x\n"))
    (with-current-buffer (+test-buffer "no file.md")
      (markdown-mode))
    (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
      (+test-md--file "terminal-notice.md" "x\n"))
    (should-not +test-md--notices)
    ;; Its preview on already.
    (let ((md (+test-md--file "on.md" "x\n")))
      (+test-md--open-preview md)
      (setq +test-md--notices nil)
      (with-current-buffer md (+my/markdown-preview-notice-h))
      (should-not (seq-find (lambda (n) (eq (car n) 'show)) +test-md--notices)))))

(ert-deftest markdown/notice-stays-when-the-preview-opens ()
  "Opened (its button, SPC m p) or closed, the preview leaves the notice."
  (+test-md
    (let ((md (+test-md--file "stays.md" "# Stays\n")))
      (setq +test-md--notices nil)
      (with-current-buffer md (+my/markdown-preview-show))
      (+test-md--redisplay)
      (with-current-buffer md (+md-preview-mode -1))
      (should-not +test-md--notices))))

(defun +test-md--preview-windows (md)
  (get-buffer-window-list (buffer-local-value '+md-preview--buffer md) nil t))

(ert-deftest markdown/open-preview-twice-opens-it-once ()
  "The notice's Open preview clicked twice: one preview, in one pane."
  (+test-md
    (let ((md (+test-md--file "twice.md" "# Twice\n")))
      (with-current-buffer md
        (+my/markdown-preview-show)
        (+test-md--redisplay)
        (let ((preview +md-preview--buffer)
              (windows (window-list)))
          (+my/markdown-preview-show)
          (+test-md--redisplay)
          (should +md-preview-mode)
          (should (eq +md-preview--buffer preview))
          (should (equal (window-list) windows))
          (should (= (length (+test-md--preview-windows md)) 1))
          (should (= (length (seq-filter (lambda (b) (string-prefix-p "Preview: twice.md" (buffer-name b)))
                                         (buffer-list)))
                     1)))))))

(ert-deftest markdown/open-preview-after-its-pane-closed ()
  "Its pane closed (its tab's ✕, the window deleted), the preview stays on:
Open preview (and SPC m p) shows it again, not off."
  (+test-md
    (let* ((md (+test-md--file "closed.md" "# Closed\n"))
           (preview (+test-md--open-preview md)))
      (delete-window (get-buffer-window preview))
      (with-current-buffer md
        (should +md-preview-mode)
        (should-not (+md-preview--shown-p))
        (+my/markdown-preview-show)
        (+test-md--redisplay)
        (should (eq +md-preview--buffer preview))
        (should (= (length (+test-md--preview-windows md)) 1))
        (should (eq (selected-window) (get-buffer-window md))))
      ;; SPC m p: shown again too.
      (delete-window (get-buffer-window preview))
      (with-current-buffer md
        (+my/markdown-preview-toggle)
        (should +md-preview-mode)
        (should (= (length (+test-md--preview-windows md)) 1))
        ;; On screen: SPC m p closes it.
        (+my/markdown-preview-toggle)
        (should-not +md-preview-mode)
        (should-not (buffer-live-p preview))))))

(ert-deftest markdown/open-preview-after-it-was-killed ()
  "Its buffer killed (q in it): Open preview opens a new one."
  (+test-md
    (let* ((md (+test-md--file "killed.md" "# Killed\n"))
           (preview (+test-md--open-preview md)))
      (kill-buffer preview)
      (with-current-buffer md
        (should-not +md-preview-mode)
        (+my/markdown-preview-show)
        (+test-md--redisplay)
        (should +md-preview-mode)
        (should (buffer-live-p +md-preview--buffer))
        (should-not (eq +md-preview--buffer preview))
        (should (= (length (+test-md--preview-windows md)) 1))))))

(ert-deftest markdown/open-preview-in-a-terminal ()
  "Without the live preview (a terminal): markdown-mode's, turned on, not
toggled off by a second click."
  (+test-md
    (let ((md (+test-md--file "eww.md" "# Eww\n"))
          (calls nil))
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
                ((symbol-function 'markdown-live-preview-mode)
                 (lambda (&optional arg) (push arg calls) (setq-local markdown-live-preview-mode t))))
        (with-current-buffer md
          (+my/markdown-preview-show)
          (+my/markdown-preview-show)))
      (should (equal calls '(1))))))

;; ====== THE PREVIEW'S PANE ======

(ert-deftest markdown/preview-page-mode ()
  (+test-md
    (let ((preview (+test-md--open-preview (+test-md--file "mode.md" "# Mode\n"))))
      (with-current-buffer preview
        (should (derived-mode-p '+my/webkit-mode))
        (should (eq +my/webkit-url-function #'+md-preview--url))
        (should (eq +my/webkit-background #'+md-preview--page-color))
        (should (eq +my/webkit-link-function #'+md-preview--follow))
        (should (memq #'+md-preview--closed-h kill-buffer-hook))
        (should (eq (current-local-map) +md-preview-page-mode-map))
        (should (eq evil-state 'normal))))
    (should (eq (evil-initial-state '+md-preview-page-mode) 'normal))))

(ert-deftest markdown/preview-url-of-a-closed-markdown-buffer ()
  (+test-md
    (with-temp-buffer
      (setq-local +md-preview--source (let ((b (+test-buffer "gone.md"))) (kill-buffer b) b))
      (should-not (+md-preview--url (selected-window)))
      (should-not (+md-preview--loaded (+test-md--xw-new)))
      (should-not +test-md--scripts))))

(ert-deftest markdown/run-and-update-without-a-preview ()
  (+test-md
    (let ((md (+test-md--file "none.md" "# None\n")))
      (with-current-buffer md
        (+md-preview--run "x()")
        (+md-preview--scroll)
        (+md-preview--update md)
        (+md-preview--post-command-h))
      (let ((dead (+test-buffer "dead")))
        (kill-buffer dead)
        (+md-preview--update dead))
      (should-not +test-md--scripts))))

;; ====== MARKSMAN ======

(defun +test-md--diagnostics (server messages)
  "What `lsp-diagnostic-filter' leaves of MESSAGES for a document in md/links/
(SERVER's diagnostics), their messages."
  (let* ((dir (file-name-as-directory (+test-tmp-file "md/links/")))
         (params (lsp-make-publish-diagnostics-params
                  :uri (lsp--path-to-uri (expand-file-name "doc.md" dir))
                  :diagnostics (vconcat (mapcar (lambda (message) (lsp-make-diagnostic :message message))
                                                messages)))))
    (cl-letf (((symbol-function 'lsp--workspace-server-id) (lambda (_workspace) server)))
      (let ((result (funcall lsp-diagnostic-filter params 'workspace)))
        (should (vectorp (lsp:publish-diagnostics-params-diagnostics result)))
        (append (mapcar #'lsp:diagnostic-message (lsp:publish-diagnostics-params-diagnostics result)) nil)))))

(ert-deftest markdown/marksman-false-link-warnings-dropped ()
  (should (eq lsp-diagnostic-filter #'+md--drop-false-link-warnings))
  (+test-file "md/links/other.md" "# One\n# Two\n")
  (+test-file "md/links/sub/my file.md" "x")
  (+test-file "md/links/ignored.md" "x")
  (+test-file "md/links/ü文.md" "x")
  (+test-file "md/links/README.md" "x")
  (let ((kept (+test-md--diagnostics
               'marksman
               '("Ambiguous link to document 'other.md'"            ; a file: dropped
                 "Ambiguous link to document 'missing.md'"
                 "Link to non-existent document 'ignored.md'"       ; git ignores it
                 "Link to non-existent document 'missing.md'"
                 "Link to non-existent document 'sub/my%20file.md#a-heading'"
                 "Link to non-existent document 'ü文.md'"
                 "Link to non-existent document '%C3%BC%E6%96%87.md'"
                 "Ambiguous link to document 'README'"              ; [[README]]: really ambiguous
                 "Link to non-existent document 'sub'"              ; a folder
                 "Unused link definition"
                 "Ambiguous link to document 'other.md' (and more)"))))
    (should (equal kept '("Ambiguous link to document 'missing.md'"
                          "Link to non-existent document 'missing.md'"
                          "Ambiguous link to document 'README'"
                          "Link to non-existent document 'sub'"
                          "Unused link definition"
                          "Ambiguous link to document 'other.md' (and more)")))))

(ert-deftest markdown/other-servers-diagnostics-kept ()
  (+test-file "md/links/other.md" "x")
  (should (equal (+test-md--diagnostics 'ltex '("Ambiguous link to document 'other.md'"))
                 '("Ambiguous link to document 'other.md'"))))

;; ====== KEYS ======

(defun +test-md--key (map state key)
  (lookup-key (evil-get-auxiliary-keymap map state) (kbd key)))

(ert-deftest markdown/keys ()
  (should (eq (+test-md--key markdown-mode-map 'normal "SPC m p") #'+my/markdown-preview-toggle))
  (should (eq (+test-md--key markdown-mode-map 'normal "SPC m P") #'markdown-preview))
  (when (require 'markdown-ts-mode nil t)
    (should (eq (+test-md--key markdown-ts-mode-map 'normal "SPC m p") #'+my/markdown-preview-toggle))
    (should (eq (+test-md--key markdown-ts-mode-map 'normal "SPC m P") #'markdown-preview)))
  ;; The preview's pane: a WebKit page's keys.
  (pcase-dolist (`(,key . ,command)
                 '(("j" . +my/webkit-scroll-down) ("k" . +my/webkit-scroll-up)
                   ("<down>" . +my/webkit-scroll-down) ("<up>" . +my/webkit-scroll-up)
                   ("C-d" . +my/webkit-half-screen-down) ("C-u" . +my/webkit-half-screen-up)
                   ("C-f" . +my/webkit-screen-down) ("C-b" . +my/webkit-screen-up)
                   ("<next>" . +my/webkit-screen-down) ("<prior>" . +my/webkit-screen-up)
                   ("gg" . +my/webkit-top) ("G" . +my/webkit-bottom)
                   ("<home>" . +my/webkit-top) ("<end>" . +my/webkit-bottom)
                   ("y" . +my/webkit-copy) ("q" . kill-current-buffer)))
    (dolist (state '(normal motion))
      (should (eq (+test-md--key +md-preview-page-mode-map state key) command))))
  (should (eq (lookup-key +md-preview-page-mode-map (kbd "s-c")) #'+my/webkit-copy))
  (should (eq (lookup-key +md-preview-page-mode-map "q") #'kill-current-buffer))
  (should (eq (lookup-key +md-preview-page-mode-map [down-mouse-1]) #'+my/webkit-mouse-select))
  (should (eq (+test-md--key +md-preview-page-mode-map 'visual "<drag-mouse-1>") #'ignore)))
