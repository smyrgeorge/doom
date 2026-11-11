;;; tests/e2e/test-pdf.el -*- lexical-binding: t; -*-
;; config/pdf.el in a GUI Emacs: real PDFs in WebKit, drawn by PDF.js
;; (a copy of Doom's, never downloaded here). Pages, splits, settings,
;; outline, history, search, zoom, copy, Option+Enter, the toolbar's
;; requests, places, links out, revert, no PDF.js, closing.
;; run.sh: alone. PDF.js draws no page while its frame is covered (macOS
;; takes it as hidden), and the frames of tests run beside it would be.

(+test-load "config/childframe" "config/banner" "config/window" "config/editor" "config/webkit" "config/pdf")

;; ====== SETUP ======

;; PDF.js: Doom's, copied into the temp data folder (`+my/pdf-js-dir' is
;; there already: `doom-data-dir' is the temp one).
(defvar +test-pdf--pdfjs (+test-pdfjs-dir))

;; Nothing opens outside Emacs: printing (osascript's Preview dialog on macOS,
;; lp on Linux) is recorded instead; the apps config/os.el starts, by
;; tests/helper.el (`+test-os-runs').
(defvar +test-pdf--outside nil
  "The commands that would have run outside Emacs, the latest first.")

(advice-add 'call-process :around
            (lambda (fn program &rest args)
              (if (equal program "lp")
                  (progn (push (cons program args) +test-pdf--outside) 0)
                (apply fn program args)))
            '((name . +test-pdf-no-lp)))

(advice-add 'make-process :around
            (lambda (fn &rest args)
              (let ((command (plist-get args :command)))
                (if (equal (car command) "osascript")
                    (progn (push command +test-pdf--outside) nil)
                  (apply fn args))))
            '((name . +test-pdf-no-osascript)))

(defun +test-pdf--file (name &rest args)
  "A PDF NAME in the temp folder (see `+test-make-pdf' for ARGS)."
  (apply #'+test-make-pdf (+test-tmp-file (concat "pdfs/" name)) args))

(defvar +test-pdf--book
  (+test-pdf--file "book.pdf" :pages 3
                   :outline '(("Chapter 1" . 1) ("Chapter 2" . 3))
                   :links '((2 . "https://example.com/pdf-link"))))

;; ====== HELPERS ======

(defun +test-pdf--state (&optional window)
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (+my/pdf--state (+my/webkit-xwidget window)))))

(defun +test-pdf--page (&optional window)
  (plist-get (+test-pdf--state window) :page))

(defun +test-pdf--wait-page (page &optional window)
  (+test-wait-for (lambda () (eql (+test-pdf--page window) page)) 5))

(defun +test-pdf--ready (&optional window)
  "WINDOW's view of its PDF, once PDF.js has opened it and drawn page 1's
text."
  (let ((window (or window (selected-window))))
    (+test-wait-for
     (lambda ()
       (with-current-buffer (window-buffer window)
         (let ((xwidget (+my/webkit-xwidget window)))
           (and xwidget
                (xwidget-view-lookup xwidget window)
                (natnump (plist-get (+test-pdf--state window) :pages))
                (> (plist-get (+test-pdf--state window) :pages) 0)
                (equal (+test-js xwidget "String(document.querySelectorAll('.textLayer span').length > 0)")
                       "true")
                xwidget))))
     15)))

(defun +test-pdf--open (file)
  "FILE opened in the selected window, ready."
  (find-file file)
  (should (derived-mode-p '+my/pdf-mode))
  (should (+test-pdf--ready))
  (current-buffer))

(defun +test-pdf--js (script &optional window)
  "SCRIPT's value in WINDOW's page (waited for)."
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (+test-js (+my/webkit-xwidget window) script))))

(defun +test-pdf--mode-line (window)
  "WINDOW's mode line's page, as doom-modeline's PDF line shows it."
  (with-current-buffer (window-buffer window)
    (string-trim (format-mode-line '("" doom-modeline--pdf-pages) nil window))))

(defun +test-pdf--click (title &optional window)
  "Click the toolbar button whose title starts with TITLE."
  (+test-pdf--js (format "[...document.querySelectorAll('#toolbar button')].find(b => b.title.startsWith(%S)).click(); 'ok'"
                         title)
                 window))

(defmacro +test-pdf (&rest body)
  "BODY with PDF.js there, from one window; the PDFs closed after."
  (declare (indent 0))
  `(progn
     (+test-needs-webkit)
     (unless +test-pdf--pdfjs
       (ert-skip "No PDF.js in Doom's data folder (open a PDF in Emacs once)"))
     (+test-with-reset
       (setq +test-browsed nil
             +test-pdf--outside nil
             +my/pdf-dark-pages nil
             +my/pdf-toolbar t
             +my/pdf-outline-sidebar nil)
       ;; No place kept from another test (closing a PDF keeps its place:
       ;; the reset closed the last test's).
       (setq +my/pdf--places nil)
       (when (file-exists-p +my/pdf-places-file)
         (delete-file +my/pdf-places-file))
       (+test-clear-messages)
       ,@body
       (+test-sleep 0.2))))

;; ====== OPENING ======

(ert-deftest e2e-pdf/opens-in-webkit-with-pdfjs ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (should (eq major-mode '+my/pdf-mode))
    (should-not +my/pdf--native)
    (should (string-suffix-p "/index.html" +my/pdf--home))
    (should (file-exists-p (expand-file-name "data-1.js" +my/pdf--dir)))
    (let ((state (+test-pdf--state)))
      (should (eql (plist-get state :pages) 3))
      (should (eql (plist-get state :page) 1))
      (should (plist-get state :toolbar))
      (should-not (plist-get state :dark)))
    (should (+test-wait-for (lambda () (equal (+test-pdf--mode-line (selected-window)) "P1/3")) 3))
    ;; The page's text, selectable.
    (should (string-match-p "Page 1 text"
                            (+test-pdf--js "document.querySelector('.textLayer').textContent")))))

(ert-deftest e2e-pdf/a-file-name-with-spaces-and-a-hash ()
  (+test-pdf
    (let ((file (+test-pdf--file "my file #1 é.pdf" :pages 2)))
      (+test-pdf--open file)
      (should (eql (plist-get (+test-pdf--state) :pages) 2)))))

(ert-deftest e2e-pdf/without-pdfjs-webkit-s-own-viewer ()
  (+test-pdf
    (let ((+my/pdf-js-dir (+test-tmp-file "no-pdfjs/"))
          (file (+test-pdf--file "native.pdf" :pages 1)))
      (cl-letf (((symbol-function '+my/pdf-js-install)
                 (lambda () (error "Offline"))))
        (find-file file)
        (should (+test-wait-for (lambda () (+my/webkit-xwidget (selected-window))) 10))
        (should +my/pdf--native)
        (should (equal +my/pdf--home (+my/webkit-file-url file)))
        (should (> (+test-messages "own viewer: Offline") 0)) ; WebKit’s: `message' curls it
        ;; Keys that need PDF.js say so.
        (+my/pdf-next-page)
        (should (> (+test-messages "No PDF.js here") 0))))))

;; ====== PAGES ======

(ert-deftest e2e-pdf/pages-and-scrolling ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 2))
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 3))
    (+my/pdf-previous-page 2)
    (should (+test-pdf--wait-page 1))
    (+my/pdf-bottom)
    (should (+test-pdf--wait-page 3))
    (+my/pdf-top)
    (should (+test-pdf--wait-page 1))
    (+my/pdf-top 2)                ; 2gg: page 2
    (should (+test-pdf--wait-page 2))
    (should (+test-wait-for (lambda () (equal (+test-pdf--mode-line (selected-window)) "P2/3")) 3))
    (+my/pdf-top)
    (should (+test-pdf--wait-page 1))
    (let ((y (string-to-number (+test-pdf--js "String(document.getElementById('viewerContainer').scrollTop)"))))
      (+my/pdf-scroll-down 3)
      (should (+test-wait-for
               (lambda () (> (string-to-number (+test-pdf--js "String(document.getElementById('viewerContainer').scrollTop)"))
                             y))
               3)))))

(ert-deftest e2e-pdf/zoom-and-fit ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let ((scale (lambda () (plist-get (plist-get (+test-pdf--state) :place) :s))))
      (should (equal (funcall scale) "page-width"))
      (+my/pdf-actual-size)
      (should (+test-wait-for (lambda () (equal (funcall scale) "page-actual")) 3))
      (+my/pdf-zoom-in)
      (should (+test-wait-for (lambda () (numberp (funcall scale))) 3))
      (let ((zoomed (funcall scale)))
        (should (> zoomed 100))
        (+my/pdf-zoom-out)
        (should (+test-wait-for (lambda () (let ((s (funcall scale))) (and (numberp s) (< s zoomed)))) 3)))
      (+my/pdf-fit-page)
      (should (+test-wait-for (lambda () (equal (funcall scale) "page-fit")) 3))
      (+my/pdf-fit-width)
      (should (+test-wait-for (lambda () (equal (funcall scale) "page-width")) 3)))))

;; ====== SPLITS ======

(ert-deftest e2e-pdf/split-panes-show-the-pdf-apart ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (should (+test-pdf--ready right))
      (should (= (+test-messages "share an xwidget") 0))
      (select-window right)
      (+my/pdf-bottom)
      (should (+test-pdf--wait-page 3 right))
      (should (eql (+test-pdf--page left) 1))
      ;; Each mode line its pane's page.
      (should (+test-wait-for (lambda () (and (equal (+test-pdf--mode-line right) "P3/3")
                                              (equal (+test-pdf--mode-line left) "P1/3")))
                              3)))))

(ert-deftest e2e-pdf/a-new-pane-starts-where-the-pdf-was ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-bottom)
    (should (+test-pdf--wait-page 3))
    (+test-sleep 0.3)                     ; its place said in its title
    (let ((right (split-window-right)))
      (should (+test-pdf--ready right))
      (should (+test-pdf--wait-page 3 right)))))

(ert-deftest e2e-pdf/settings-apply-to-all-panes ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (should (+test-pdf--ready right))
      (+my/pdf-toggle-dark)
      (should +my/pdf-dark-pages)
      (should (+test-wait-for (lambda () (and (plist-get (+test-pdf--state left) :dark)
                                              (plist-get (+test-pdf--state right) :dark)))
                              3))
      (+my/pdf-toggle-toolbar)
      (should-not +my/pdf-toolbar)
      (should (+test-wait-for (lambda () (not (or (plist-get (+test-pdf--state left) :toolbar)
                                                  (plist-get (+test-pdf--state right) :toolbar))))
                              3))
      (+my/pdf-toggle-sidebar)
      (should +my/pdf-outline-sidebar)
      (should (+test-wait-for (lambda () (and (plist-get (+test-pdf--state left) :sidebar)
                                              (plist-get (+test-pdf--state right) :sidebar)))
                              3)))))

(ert-deftest e2e-pdf/the-next-pdf-opens-with-the-last-settings ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-toggle-dark)
    (should (+test-wait-for (lambda () (plist-get (+test-pdf--state) :dark)) 3))
    (+test-pdf--open (+test-pdf--file "second.pdf" :pages 1))
    (should (plist-get (+test-pdf--state) :dark))))

;; ====== OUTLINE, HISTORY, SEARCH ======

(ert-deftest e2e-pdf/the-outline-in-the-minibuffer ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq offered (all-completions "" collection))
                   "Chapter 2")))
        (+my/pdf-outline)
        (should (+test-pdf--wait-page 3)))
      (should (equal (mapcar #'substring-no-properties offered) '("Chapter 1" "Chapter 2"))))))

(ert-deftest e2e-pdf/back-and-forward ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf--js "outlineGo(1)")  ; Chapter 2, a jump
    (should (+test-pdf--wait-page 3))
    (+my/pdf-back)
    (should (+test-pdf--wait-page 1))
    (+my/pdf-forward)
    (should (+test-pdf--wait-page 3))))

(ert-deftest e2e-pdf/search ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf--find "page   3\n text")   ; spaces and lines as one space
    (should +my/pdf--searching)
    (should (+test-pdf--wait-page 3))
    (should (+test-wait-for (lambda () (> (string-to-number
                                           (+test-pdf--js "String(document.querySelectorAll('.highlight').length)"))
                                          0))
                            5))
    ;; Esc ends it: the highlights go.
    (should (+my/pdf--escape-h))
    (should-not +my/pdf--searching)
    (should (+test-wait-for (lambda () (equal (+test-pdf--js "String(document.querySelectorAll('.highlight.selected').length)")
                                              "0"))
                            5))
    (should-not (+my/pdf--escape-h))))

(ert-deftest e2e-pdf/search-is-case-sensitive-with-a-capital ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-bottom)
    (should (+test-pdf--wait-page 3))
    (+my/pdf--find "PAGE 1")         ; no match: stays
    (+test-sleep 0.8)
    (should (eql (+test-pdf--page) 3))
    (+my/pdf--find "page 1")         ; lower case: any case
    (should (+test-pdf--wait-page 1))))

;; ====== SIDEBAR ======

(ert-deftest e2e-pdf/thumbnails ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf--js "set({sidebar: true, view: 'pages'})")
    (should (+test-wait-for (lambda () (equal (+test-pdf--js "String(document.querySelectorAll('#sidebar .thumb canvas').length)")
                                              "3"))
                            10))
    (+test-pdf--js "document.querySelectorAll('#sidebar .thumb')[2].click(); 'ok'")
    (should (+test-pdf--wait-page 3))
    (should (equal (+test-pdf--js "document.querySelector('#sidebar .thumb.current .num').textContent") "3"))))

(ert-deftest e2e-pdf/the-outline-sidebar ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf--js "set({sidebar: true, view: 'outline'})")
    (should (+test-wait-for (lambda () (equal (+test-pdf--js "String(document.querySelectorAll('#sidebar .item').length)")
                                              "2"))
                            5))
    (+test-pdf--js "document.querySelectorAll('#sidebar .item')[1].click(); 'ok'")
    (should (+test-pdf--wait-page 3))))

;; ====== COPY, OPTION+ENTER ======

(defun +test-pdf--select-page-text (&optional window)
  (+test-pdf--js "var r = document.createRange();
r.selectNodeContents(document.querySelector('.textLayer'));
var s = getSelection(); s.removeAllRanges(); s.addRange(r); String(s).trim()"
                 window))

(ert-deftest e2e-pdf/copy-the-selection ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let ((kill-ring nil))
      (should (string-match-p "Page 1 text" (+test-pdf--select-page-text)))
      (+my/webkit-copy)
      (should (+test-wait-for (lambda () kill-ring) 3))
      (should (string-match-p "Page 1 text" (car kill-ring))))))

(defun +test-pdf--actions ()
  "The Option+Enter menu's actions, as (GROUP NAME), from the PDF's page."
  (let (shown)
    (cl-letf (((symbol-function '+my/context-actions)
               (lambda () (setq shown (mapcar (lambda (a) (list (nth 0 a) (nth 1 a)))
                                              (+my/context-actions-pdf))))))
      (+my/pdf-actions)
      (+test-wait-for (lambda () shown) 3))
    shown))

(ert-deftest e2e-pdf/option-enter-with-a-selection ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+test-pdf--select-page-text)
    (let ((actions (+test-pdf--actions)))
      (should (member '("PDF" "Copy") actions))
      (should (member '("PDF" "Search the PDF for it") actions))
      (should (member '("PDF" "Search the web for it") actions))
      (should (member '("Claude" "Explain selection with Claude") actions))
      (should (member '("Claude" "Add selection to Claude prompt") actions))
      (should (member '("PDF" "Open in Preview") actions))
      (should (member '("PDF" "Print...") actions)))
    ;; The provider comes first in the menu (config/editor.el's list).
    (should (eq (car +my/context-action-providers) #'+my/context-actions-pdf))))

(ert-deftest e2e-pdf/option-enter-without-a-selection ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (should (equal (+test-pdf--actions)
                   '(("PDF" "Open in Preview") ("PDF" "Print..."))))))

(ert-deftest e2e-pdf/claude-is-told-the-file-and-page ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 2))
    (let ((text (funcall (+my/pdf--claude-context "Some  quoted\ntext ")
                         (file-name-directory +test-pdf--book))))
      (should (equal text "From book.pdf, page 2:\n\n> Some  quoted\n> text")))))

;; ====== PREVIEW, PRINT ======

(ert-deftest e2e-pdf/the-toolbar-s-preview-and-print ()
  "The toolbar's Open in Preview (Linux: the default app) and Print
(Preview's dialog; Linux: lp, after asking), each run once."
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (setq +test-os-runs nil)
    (+test-pdf--click (concat "Open in " (+my/os-app-name 'viewer)))
    (should (+test-wait-for (lambda () +test-os-runs) 3))
    (should (equal (car +test-os-runs)
                   (if (+my/macos-p)
                       (list "open" "-a" "Preview" +test-pdf--book)
                     (list "xdg-open" +test-pdf--book))))
    (let ((find (symbol-function 'executable-find)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t))
                ((symbol-function 'executable-find)
                 (lambda (name &rest args) (if (equal name "lp") "/usr/bin/lp" (apply find name args)))))
        (+test-pdf--click "Print")
        (should (+test-wait-for (lambda () +test-pdf--outside) 3))))
    (should (equal (car (car +test-pdf--outside)) (if (+my/macos-p) "osascript" "lp")))
    (should (equal (car (last (car +test-pdf--outside))) +test-pdf--book))
    ;; Each request runs once.
    (+test-sleep 0.5)
    (should (= (length +test-pdf--outside) 1))
    (should (= (length +test-os-runs) 1))))

;; ====== LINKS OUT ======

(ert-deftest e2e-pdf/a-link-in-the-pdf-opens-in-the-browser ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 2))
    (should (+test-wait-for (lambda () (equal (+test-pdf--js "String(!!document.querySelector('.annotationLayer a[href^=\"https\"]'))")
                                              "true"))
                            5))
    (+test-pdf--js "document.querySelector('.annotationLayer a[href^=\"https\"]').click(); 'ok'")
    (should (+test-wait-for (lambda () +test-browsed) 5))
    (should (equal +test-browsed '("https://example.com/pdf-link")))
    ;; Still the PDF, where it was.
    (should (+test-pdf--ready))
    (should (string-suffix-p "/index.html" (xwidget-webkit-uri (+my/webkit-xwidget (selected-window)))))))

;; ====== PLACES, REVERT, CLOSING ======

(ert-deftest e2e-pdf/a-pdf-opens-where-it-was-closed ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 2))
    (+test-sleep 0.3)
    (kill-buffer (current-buffer))
    (should (file-exists-p +my/pdf-places-file))
    (should (assoc (abbreviate-file-name +test-pdf--book) (+my/pdf--read-places)))
    (+test-pdf--open +test-pdf--book)
    (should (+test-pdf--wait-page 2))))

(ert-deftest e2e-pdf/places-survive-a-restart ()
  "Kept in the places file: read anew (as after a restart) they're there."
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-bottom)
    (should (+test-pdf--wait-page 3))
    (+test-sleep 0.3)
    (kill-buffer (current-buffer))
    (setq +my/pdf--places 'unread)
    (should (eql (plist-get (cdr (assoc (abbreviate-file-name +test-pdf--book)
                                        (+my/pdf--read-places)))
                            :p)
                 3))))

(ert-deftest e2e-pdf/quitting-emacs-keeps-places-and-cleans-up ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (+my/pdf-next-page)
    (should (+test-pdf--wait-page 2))
    (+test-sleep 0.3)
    (setq +my/pdf--places nil)
    (let ((dir +my/pdf--dir))
      (+my/pdf--cleanup-h)
      (should-not (file-directory-p dir))
      (should (assoc (abbreviate-file-name +test-pdf--book) +my/pdf--places)))))

(ert-deftest e2e-pdf/a-changed-pdf-is-shown-anew-where-it-was ()
  (+test-pdf
    (let ((file (+test-pdf--file "changing.pdf" :pages 3)))
      (+test-pdf--open file)
      (+my/pdf-next-page)
      (should (+test-pdf--wait-page 2))
      (+test-make-pdf file :pages 5)
      (revert-buffer t t)
      (should (+test-wait-for (lambda () (eql (plist-get (+test-pdf--state) :pages) 5)) 10))
      (should (eql (+test-pdf--page) 2))
      (should (file-exists-p (expand-file-name "data-2.js" +my/pdf--dir)))
      (should-not (file-exists-p (expand-file-name "data-1.js" +my/pdf--dir))))))

(ert-deftest e2e-pdf/closing-deletes-the-page-s-folder ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let ((dir +my/pdf--dir)
          (xwidget (+my/webkit-xwidget (selected-window))))
      (should (file-directory-p dir))
      (+test-sleep 0.2)
      (kill-buffer (current-buffer))
      (should-not (file-directory-p dir))
      (should-not (memq xwidget (bound-and-true-p xwidget-list))))))

(ert-deftest e2e-pdf/q-closes ()
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (let ((buffer (current-buffer)))
      (+test-sleep 0.2)
      (execute-kbd-macro "q")
      (should-not (buffer-live-p buffer)))))

;; ====== THE THEME ======

(ert-deftest e2e-pdf/a-theme-change-repaints-the-page ()
  "A theme loaded: the open PDF's page takes its colours (the CSS
variables PDF.js's toolbar and sidebar use, its background)."
  (+test-pdf
    (+test-pdf--open +test-pdf--book)
    (cl-letf* ((frame-parameter (symbol-function 'frame-parameter))
               ((symbol-function 'frame-parameter)
                (lambda (frame parameter)
                  (if (eq parameter 'background-mode)
                      'light
                    (funcall frame-parameter frame parameter))))
               ((symbol-function '+my/pdf--color)
                (lambda (_face attribute _fallback)
                  (if (eq attribute :background) "#fafafa" "#383a42"))))
      ;; As Doom runs it: from `enable-theme-functions', in a temp buffer.
      (with-temp-buffer
        (run-hooks 'doom-load-theme-hook)))
    (should (+test-wait-for
             (lambda ()
               (equal (+test-pdf--js "getComputedStyle(document.body).backgroundColor")
                      "rgb(250, 250, 250)"))
             3))
    (should (equal (+test-pdf--js "getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()")
                   "#fafafa"))
    (should (equal (+test-pdf--js "getComputedStyle(document.documentElement).colorScheme")
                   "light"))
    ;; The badges (search, page) too: the theme's bar and text.
    (should (equal (+test-pdf--js "getComputedStyle(document.getElementById('page')).backgroundColor")
                   "rgb(250, 250, 250)"))
    (should (equal (+test-pdf--js "getComputedStyle(document.getElementById('find')).color")
                   "rgb(56, 58, 66)"))
    ;; PDF.js still there: the page's drawn text untouched.
    (should (eql (plist-get (+test-pdf--state) :pages) 3))))
