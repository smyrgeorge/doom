;;; tests/e2e/test-markdown.el -*- lexical-binding: t; -*-
;; config/markdown.el's live preview in a GUI Emacs: pandoc's HTML in WebKit
;; (config/webkit.el) beside the file, following the cursor and the typing,
;; splits, links, keys, closing.

(require 'markdown-mode)
;; The preview's stylesheets (Doom's markdown module sets GitHub's).
(setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css"))

(+test-load "config/banner" "config/window" "config/webkit" "config/markdown")

;; ====== SETUP ======

(defvar +test-md--doc
  (+test-file "md/doc.md"
              (concat "# First part\n\n"
                      "Jump to [the second part](#second-part), see [the other file](other.md) "
                      "or [the web](https://example.com/page).\n\n"
                      (mapconcat (lambda (i) (format "Paragraph %d of the first part, some words to fill a line." i))
                                 (number-sequence 1 40) "\n\n")
                      "\n\n## Second part\n\n"
                      (mapconcat (lambda (i) (format "Paragraph %d of the second part." i))
                                 (number-sequence 1 40) "\n\n")
                      "\n")))

(defvar +test-md--other (+test-file "md/other.md" "# Other\n\nThe other file.\n"))

;; ====== HELPERS ======

(defun +test-md--source ()
  (get-file-buffer +test-md--doc))

(defun +test-md--preview ()
  (buffer-local-value '+md-preview--buffer (+test-md--source)))

(defun +test-md--windows ()
  (get-buffer-window-list (+test-md--preview) nil t))

(defun +test-md--js (window script)
  (with-current-buffer (window-buffer window)
    (+test-js (+my/webkit-xwidget window) script)))

(defun +test-md--ready (window)
  "WINDOW's view of the preview, once its page shows the Markdown."
  (+test-wait-for
   (lambda ()
     (with-current-buffer (window-buffer window)
       (let ((xwidget (+my/webkit-xwidget window)))
         (and xwidget
              (xwidget-view-lookup xwidget window)
              (> (string-to-number (+test-js xwidget "String(document.querySelectorAll('[data-pos]').length)"))
                 0)
              xwidget))))
   15))

(defun +test-md--scroll-y (window)
  (string-to-number (+test-md--js window "String(Math.round(scrollY))")))

(defun +test-md--has (window text)
  (equal (+test-md--js window (format "String(document.body.innerText.indexOf(%S) >= 0)" text))
         "true"))

(defun +test-md--open ()
  "doc.md in markdown-mode, its preview on (SPC m p), loaded."
  (find-file +test-md--doc)
  (markdown-mode)
  (goto-char (point-min))
  (let ((this-command '+my/markdown-preview-toggle))
    (+my/markdown-preview-toggle))
  (should +md-preview-mode)
  (should (= (length (+test-md--windows)) 1))
  (should (+test-md--ready (car (+test-md--windows)))))

(defmacro +test-md (&rest body)
  "BODY with pandoc there, from one window; the preview and files closed after."
  (declare (indent 0))
  `(progn
     (unless (executable-find "pandoc")
       (ert-skip "No pandoc"))
     (+test-with-reset
       (setq +test-browsed nil)
       (+test-clear-messages)
       ,@body
       (+test-sleep 0.2))))

;; ====== OPENING ======

(ert-deftest e2e-markdown/opens-beside-the-file ()
  (+test-md
    (let ((source-window (selected-window))
          (width (window-total-width)))
      (+test-md--open)
      (let ((preview-window (car (+test-md--windows))))
        ;; On the right, half the file's window; the cursor stays in the file.
        (should (eq (selected-window) source-window))
        (should (> (car (window-edges preview-window)) (car (window-edges source-window))))
        (should (<= (abs (- (window-total-width preview-window) (/ width 2))) 2))
        (should (equal (buffer-name (+test-md--preview)) "Preview: doc.md"))
        (with-current-buffer (+test-md--preview)
          (should (eq major-mode '+md-preview-page-mode)))
        (should (+test-md--has preview-window "Paragraph 40 of the second part"))
        ;; pandoc's sourcepos, for following the cursor.
        (should (equal (+test-md--js preview-window "document.querySelector('h1').getAttribute('data-pos').split(':')[0]")
                       "1"))))))

(ert-deftest e2e-markdown/the-notice-goes-once-the-preview-opens ()
  (+test-md
    (find-file +test-md--doc)
    (markdown-mode)
    (should (assq 'markdown-preview +my/banner--list))
    (let ((this-command '+my/markdown-preview-toggle))
      (+my/markdown-preview-toggle))
    (should-not (assq 'markdown-preview +my/banner--list))))

(ert-deftest e2e-markdown/the-pane-is-the-page-s-colour ()
  (+test-md
    (let (covers)
      (advice-add '+my/webkit--cover :after
                  (lambda (_window xwidget)
                    (when-let* ((cover (xwidget-get xwidget 'cover)))
                      (push (frame-parameter (car cover) 'background-color) covers)))
                  '((name . +test-md-cover)))
      (unwind-protect (+test-md--open)
        (advice-remove '+my/webkit--cover '+test-md-cover))
      (should (equal covers (list (+md-preview--page-color)))))))

;; ====== FOLLOWING THE FILE ======

(ert-deftest e2e-markdown/follows-the-cursor ()
  (+test-md
    (+test-md--open)
    (let ((preview-window (car (+test-md--windows))))
      (should (= (+test-md--scroll-y preview-window) 0))
      (with-current-buffer (+test-md--source)
        (goto-char (point-min))
        (forward-line 60)
        (+md-preview--post-command-h))
      (should (+test-wait-for (lambda () (> (+test-md--scroll-y preview-window) 500)) 3))
      (with-current-buffer (+test-md--source)
        (goto-char (point-min))
        (+md-preview--post-command-h))
      (should (+test-wait-for (lambda () (= (+test-md--scroll-y preview-window) 0)) 3)))))

(ert-deftest e2e-markdown/updates-as-you-type ()
  (+test-md
    (+test-md--open)
    (let ((preview-window (car (+test-md--windows))))
      (with-current-buffer (+test-md--source)
        (goto-char (point-max))
        (insert "\nTYPED just now\n"))
      ;; After 0.3 s without typing.
      (should (+test-wait-for (lambda () (+test-md--has preview-window "TYPED just now")) 5))
      ;; Swapped in, not reloaded: the same page.
      (should (equal (+test-md--js preview-window "location.href")
                     (+my/webkit-file-url (buffer-local-value '+md-preview--file (+test-md--source))))))))

;; ====== SPLITS ======

(ert-deftest e2e-markdown/split-both-panes-show-it ()
  (+test-md
    (+test-md--open)
    (with-current-buffer (+test-md--source)
      (goto-char (point-min))
      (forward-line 60)
      (+md-preview--post-command-h))
    (let* ((top (car (+test-md--windows)))
           (below (with-selected-window top (split-window-below))))
      (should (+test-md--ready below))
      (should (= (+test-messages "share an xwidget") 0))
      ;; The new view at the cursor's line too.
      (should (+test-wait-for (lambda () (> (+test-md--scroll-y below) 500)) 3))
      ;; Typing reaches both.
      (with-current-buffer (+test-md--source)
        (goto-char (point-max))
        (insert "\nBOTH panes\n")
        (+md-preview--update (current-buffer)))
      (should (+test-wait-for (lambda () (and (+test-md--has top "BOTH panes")
                                              (+test-md--has below "BOTH panes")))
                              5))
      ;; One closed: its view goes, the preview stays.
      (delete-window below)
      (+test-sleep 1.4)
      (should +md-preview-mode)
      (should (= (length (buffer-local-value '+my/webkit--views (+test-md--preview))) 1)))))

;; ====== LINKS ======

(defun +test-md--click (window selector)
  (+test-md--js window (format "document.querySelector(%S).click(); 'ok'" selector)))

(ert-deftest e2e-markdown/a-heading-link-scrolls-there ()
  (+test-md
    (+test-md--open)
    (let ((preview-window (car (+test-md--windows))))
      (+test-md--click preview-window "a[href=\"#second-part\"]")
      (should (+test-wait-for (lambda () (> (+test-md--scroll-y preview-window) 1000)) 3))
      (+test-sleep 0.3)
      (should-not +test-browsed)
      (should (string-suffix-p ".html" (+test-md--js preview-window "location.href"))))))

(ert-deftest e2e-markdown/a-file-link-opens-in-the-file-s-pane ()
  (+test-md
    (let ((source-window (selected-window)))
      (+test-md--open)
      (let ((preview-window (car (+test-md--windows))))
        (+test-md--click preview-window "a[href=\"other.md\"]")
        (should (+test-wait-for (lambda () (get-file-buffer +test-md--other)) 5))
        (should (eq (window-buffer source-window) (get-file-buffer +test-md--other)))
        (should (eq (selected-window) source-window))
        ;; The preview stays on its page, still showing doc.md.
        (should (+test-wait-for (lambda () (string-suffix-p ".html" (+test-md--js preview-window "location.href"))) 5))
        (should (+test-md--ready preview-window))
        (should-not +test-browsed)))))

(ert-deftest e2e-markdown/a-web-link-opens-in-the-browser ()
  (+test-md
    (+test-md--open)
    (let ((preview-window (car (+test-md--windows))))
      (with-current-buffer (+test-md--source)
        (goto-char (point-max))
        (insert "\nTYPED before the link\n")
        (+md-preview--update (current-buffer)))
      (should (+test-wait-for (lambda () (+test-md--has preview-window "TYPED before the link")) 5))
      (+test-md--click preview-window "a[href^=\"https\"]")
      (should (+test-wait-for (lambda () +test-browsed) 5))
      (should (equal +test-browsed '("https://example.com/page")))
      ;; Back on its page, with the Markdown as it is now (not as the page's
      ;; file was written).
      (+test-sleep 0.5)
      (should (+test-md--ready preview-window))
      (should (+test-wait-for (lambda () (+test-md--has preview-window "TYPED before the link")) 5)))))

;; ====== KEYS ======

(ert-deftest e2e-markdown/keys-in-the-preview ()
  (+test-md
    (+test-md--open)
    (let ((preview-window (car (+test-md--windows)))
          (kill-ring nil))
      (select-window preview-window)
      (should (eq (key-binding "j") #'+my/webkit-scroll-down))
      (execute-kbd-macro "jj")
      (should (+test-wait-for (lambda () (= (+test-md--scroll-y preview-window) (* 2 +my/webkit-scroll-step))) 3))
      (execute-kbd-macro "G")
      (should (+test-wait-for (lambda () (> (+test-md--scroll-y preview-window) 2000)) 3))
      (execute-kbd-macro "gg")
      (should (+test-wait-for (lambda () (= (+test-md--scroll-y preview-window) 0)) 3))
      ;; y copies the page's selection.
      (+test-md--js preview-window "var r = document.createRange(); r.selectNodeContents(document.querySelector('h1'));
var s = getSelection(); s.removeAllRanges(); s.addRange(r); 'ok'")
      (execute-kbd-macro "y")
      (should (+test-wait-for (lambda () kill-ring) 3))
      (should (equal (string-trim (car kill-ring)) "First part")))))

;; ====== CLOSING ======

(ert-deftest e2e-markdown/q-in-the-preview-turns-it-off ()
  (+test-md
    (+test-md--open)
    (let ((file (buffer-local-value '+md-preview--file (+test-md--source)))
          (preview (+test-md--preview)))
      (should (file-exists-p file))
      (select-window (car (+test-md--windows)))
      (+test-sleep 0.2)
      (execute-kbd-macro "q")
      (should-not (buffer-live-p preview))
      (with-current-buffer (+test-md--source)
        (should-not +md-preview-mode)
        (should-not +md-preview--file))
      (should-not (file-exists-p file)))))

(ert-deftest e2e-markdown/spc-m-p-again-closes-it ()
  (+test-md
    (+test-md--open)
    (let ((preview (+test-md--preview))
          (file (buffer-local-value '+md-preview--file (+test-md--source))))
      (+test-sleep 0.2)
      (+my/markdown-preview-toggle)
      (should-not +md-preview-mode)
      (should-not (buffer-live-p preview))
      (should-not (file-exists-p file))
      (should (= (length (window-list)) 1))
      ;; And again: a new preview.
      (let ((this-command '+my/markdown-preview-toggle))
        (+my/markdown-preview-toggle))
      (should (+test-md--ready (car (+test-md--windows)))))))

(ert-deftest e2e-markdown/closing-the-file-closes-the-preview ()
  (+test-md
    (+test-md--open)
    (let ((preview (+test-md--preview))
          (file (buffer-local-value '+md-preview--file (+test-md--source))))
      (+test-sleep 0.2)
      (kill-buffer (+test-md--source))
      (should-not (buffer-live-p preview))
      (should-not (file-exists-p file)))))

(ert-deftest e2e-markdown/off-while-its-page-loads ()
  "Turned off at once: nothing left (no view, no cover, no file), no crash."
  (+test-md
    (find-file +test-md--doc)
    (markdown-mode)
    (let ((this-command '+my/markdown-preview-toggle))
      (+my/markdown-preview-toggle))
    (let ((preview (+test-md--preview))
          (file +md-preview--file))
      (+test-sleep 0.15)                  ; the view made, loading
      (+my/markdown-preview-toggle)
      (should-not (buffer-live-p preview))
      (should-not (file-exists-p file))
      (+test-sleep 2.2)                   ; past the cover's 2 s
      (should (= (+test-visible-frames) 1)))))
