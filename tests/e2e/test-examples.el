;;; tests/e2e/test-examples.el -*- lexical-binding: t; -*-
;; The examples in a GUI Emacs: the merge example's panes on screen, its
;; wands in the Result's margin; Done, and its repository is gone. The PDF in
;; PDF.js, dark; the Markdown preview loaded; the drawing in Excalidraw; the
;; error stripe's frame shown; the notices' frame: each ready (what the
;; screenshots wait for), and its files gone once closed. What each one says:
;; one line of an 80-column frame. PDF.js and Excalidraw: copies of Doom's,
;; never downloaded here.
;; run.sh: slow (~40 s beside the others: started first).

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/emacs" "config/banner" "config/editor"
            "config/webkit" "config/pdf" "config/image" "config/markdown" "config/excalidraw" "config/stripe"
            "config/tiling" "config/merge" "config/agent-ui" "config/mermaid" "config/examples")
(require 'mermaid-mode)
(global-tab-line-mode 1)
(global-so-long-mode 1)
(setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css"))

(defvar +test-examples--pdfjs (+test-pdfjs-dir))
(defvar +test-examples--excalidraw (+test-excalidraw-dir))
(defvar +test-examples--mermaid-js (+test-mermaid-js-dir))

(defun +test-examples--folder (buffer)
  "The folder of the example BUFFER is part of."
  (car (buffer-local-value '+my/example--closing buffer)))

(ert-deftest e2e-examples/merge ()
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "examples-home-") t)))
           (process-environment
            (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                          "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0")
                    process-environment)))
      (with-temp-file (expand-file-name ".gitconfig" home))
      (call-interactively #'+my/example-merge)
      (+test-sleep 0.3)
      (let* ((session (buffer-local-value '+my/merge--session (current-buffer)))
             (repo (+my/merge-toplevel session))
             (result (get-buffer-window (+my/merge-result session))))
        (should (get-buffer-window (+my/merge-yours session)))
        (should (get-buffer-window (+my/merge-theirs session)))
        (should (get-buffer-window (+my/merge-bar session)))
        (should (eq (selected-window) result))
        ;; The wands, in the Result's margin.
        (should (equal (window-margins result) '(2)))
        (should (= 2 (with-current-buffer (+my/merge-result session)
                       (seq-count (lambda (ov)
                                    (equal (car-safe (get-text-property 0 'display (or (overlay-get ov 'before-string) " ")))
                                           '(margin left-margin)))
                                  (overlays-in (point-min) (point-max))))))
        (+my/merge-apply-non-conflicting)
        (+my/merge-accept-left)
        (+my/merge-done)
        (should-not (file-exists-p repo))
        (should-not (buffer-live-p (+my/merge-result session)))))))

(ert-deftest e2e-examples/pdf-dark ()
  "Opened in PDF.js, three pages, dark; closed: its file gone, its place not
kept, dark pages as they were."
  (+test-needs-webkit)
  (skip-unless +test-examples--pdfjs)
  (+test-with-reset
    (let* ((dark +my/pdf-dark-pages)
           (buffer (+my/example-pdf))
           (dir (+test-examples--folder buffer))
           (file buffer-file-name))
      (should (+test-wait-for #'+my/example-pdf-ready 20))
      (with-current-buffer buffer
        (should (eq major-mode '+my/pdf-mode))
        (should (= (plist-get (+my/pdf--state) :pages) 3))
        (should (plist-get (+my/pdf--state) :dark)))
      (kill-buffer buffer)
      (+test-sleep 0.3)
      (should-not (file-exists-p dir))
      (should (eq +my/pdf-dark-pages dark))
      (should-not (assoc (abbreviate-file-name file) (+my/pdf--read-places))))))

(ert-deftest e2e-examples/pdf-twice-dark-pages-put-back ()
  "Run twice, closed in either order: dark pages as they were before the
first, off or on (not as the second found them, on)."
  (+test-needs-webkit)
  (skip-unless +test-examples--pdfjs)
  (let ((saved +my/pdf-dark-pages))
    (unwind-protect
        (pcase-dolist (`(,dark . ,order) '((nil . first) (nil . last) (t . first)))
          (+test-with-reset
            (setq +my/pdf-dark-pages dark)
            (let* ((dark-p (lambda (buffer)
                             (lambda () (with-current-buffer buffer (plist-get (+my/pdf--state) :dark)))))
                   (a (+my/example-pdf))
                   (_ (should (+test-wait-for (funcall dark-p a) 20)))
                   (b (+my/example-pdf)))
              (should (+test-wait-for (funcall dark-p b) 20))
              (dolist (buffer (if (eq order 'first) (list a b) (list b a)))
                (kill-buffer buffer)
                (+test-sleep 0.3))
              (should (eq +my/pdf-dark-pages dark)))))
      (setq +my/pdf-dark-pages saved))))

(ert-deftest e2e-examples/image-beside-its-head ()
  "The picture in the image viewer, its version in git's HEAD on its left in
the same pane; closed: the repository gone."
  (+test-with-reset
    (let* ((buffer (+my/example-image))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-image-ready 20))
      (should (eq (window-buffer (selected-window)) buffer))
      (should (= (length (window-list)) 1))
      (with-current-buffer buffer
        (should (+my/image--head-shown-p))
        (should (+my/image--diff-side-p (selected-window)))
        (should (equal (+my/image-size) '(480 . 300)))
        (should (equal (+my/image--position) '(1 . 3)))) ; dawn, landscape, night
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/image-j-k-in-its-folder ()
  "J: the folder's next picture, night.png, in the image viewer (its file
there); K: back to landscape.png. The folder kept while one of its pictures
is open, deleted once the last is closed."
  (+test-with-reset
    (let* ((buffer (+my/example-image))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-image-ready 20))
      (with-current-buffer (window-buffer (selected-window))
        (+my/image-next))
      (+test-sleep 0.2)
      (with-current-buffer (window-buffer (selected-window))
        (should (equal (file-name-nondirectory buffer-file-name) "night.png"))
        (should (file-exists-p buffer-file-name))
        (should +my/image-mode)
        (should (equal (+my/image-size) '(240 . 150)))
        (+my/image-previous))
      (+test-sleep 0.2)
      (let ((landscape (window-buffer (selected-window))))
        (with-current-buffer landscape
          (should (equal (file-name-nondirectory buffer-file-name) "landscape.png"))
          (should +my/image-mode)
          (should (equal (+my/image-size) '(480 . 300))))
        (should (file-directory-p dir))
        (kill-buffer landscape))
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/markdown-and-its-preview ()
  "The README, its preview beside it, loaded; closed: the preview with it,
the file gone."
  (+test-needs-webkit)
  (skip-unless (executable-find "pandoc"))
  (+test-with-reset
    (let* ((buffer (+my/example-markdown))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-markdown-ready 20))
      (let ((preview (buffer-local-value '+md-preview--buffer buffer)))
        (should (buffer-live-p preview))
        (should (get-buffer-window preview))
        (should (eq (window-buffer (selected-window)) buffer))
        (kill-buffer buffer)
        (should-not (buffer-live-p preview)))
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/mermaid-and-its-preview ()
  "The diagram, its preview beside it, drawn; closed: the preview with it,
the file gone."
  (+test-needs-webkit)
  (skip-unless +test-examples--mermaid-js)
  (+test-with-reset
    (let* ((buffer (+my/example-mermaid))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-mermaid-ready 20))
      (let ((preview (buffer-local-value '+my/mermaid-preview--buffer buffer)))
        (should (buffer-live-p preview))
        (should (get-buffer-window preview))
        (should (eq (window-buffer (selected-window)) buffer))
        (kill-buffer buffer)
        (should-not (buffer-live-p preview)))
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/drawing-in-excalidraw ()
  "The drawing up in Excalidraw, not changed (nothing to save); closed: its
file gone."
  (+test-needs-webkit)
  (skip-unless +test-examples--excalidraw)
  (+test-with-reset
    (let* ((buffer (+my/example-excalidraw))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-excalidraw-ready 30))
      ;; The drawing alone, though tiling opens it in a new pane.
      (should (one-window-p))
      (should (eq (window-buffer (selected-window)) buffer))
      (with-current-buffer buffer
        (should (eq major-mode '+my/excalidraw-mode))
        (should-not (plist-get (+my/excalidraw--state) :error))
        (+test-sleep 1)
        (should-not (buffer-modified-p)))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/stripe-on-screen ()
  "The error stripe's frame shown over the window's margin, with flycheck's
findings and git's changes; closed: the repository gone."
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "examples-home-") t)))
           (process-environment (append (list (concat "HOME=" home) "GIT_CONFIG_NOSYSTEM=1"
                                              (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig"))
                                        process-environment))
           (buffer (+my/example-stripe))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-stripe-ready 60))
      (should (+test-wait-for (lambda ()
                                (let ((frame (nth 1 (assq (get-buffer-window buffer) +my/stripe--frames))))
                                  (and (frame-live-p frame) (+my/childframe-shown-p frame))))
                              10))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/notices-on-screen ()
  "The three notices in their frame over the window's top rows; closed: the
file gone."
  (+test-with-reset
    (let* ((buffer (+my/example-banner))
           (dir (+test-examples--folder buffer)))
      (should (= (length (buffer-local-value '+my/banner--list buffer)) 3))
      (should (+test-wait-for (lambda ()
                                (let ((frame (nth 1 (assq (get-buffer-window buffer) +my/banner--frames))))
                                  (and (frame-live-p frame) (+my/childframe-shown-p frame))))
                              10))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/agent-ui-charts-as-svg ()
  "The canvas beside the conversation, played out; its chart an SVG image as
wide as the canvas's text, the rest text; closed: the file gone."
  (+test-with-reset
    (pcase-let* ((`(,conversation ,canvas) (+my/example-agent-ui))
                 (dir (+test-examples--folder conversation)))
      (should (+test-wait-for #'+my/example-agent-ui-ready 20))
      (redisplay t)
      (let ((window (get-buffer-window canvas)))
        (should window)
        (with-current-buffer canvas
          (agent-ui--flush)
          (let* ((at (let ((pos (point-min)))
                       ;; Ids are strings: not `text-property-any' (eq).
                       (while (and pos (not (equal (get-text-property pos 'agent-ui-id) "times")))
                         (setq pos (next-single-property-change pos 'agent-ui-id)))
                       pos))
                 (image (and at (get-text-property (next-single-property-change at 'display) 'display))))
            (should (eq (car-safe image) 'image))
            (let ((size (image-size image t)))
              ;; As wide as the text the canvas draws (a column short of
              ;; its window's), and some lines high.
              (should (= (car size) (* (frame-char-width) (1- (window-max-chars-per-line window)))))
              (should (> (cdr size) (* 4 (frame-char-height))))))))
      (kill-buffer canvas)
      (kill-buffer conversation)
      (should-not (file-exists-p dir)))))

(ert-deftest e2e-examples/messages-one-line-in-80-columns ()
  "What each example says in the echo area takes one line of an 80-column
frame (they took 2 or 3 in 100 and 60 columns); a longer one, two."
  (+test-with-reset
    (unwind-protect
        (let ((lines (lambda (text)
                       (message nil)
                       (redisplay t)
                       (message "%s" text)
                       (redisplay t)
                       (window-total-height (minibuffer-window)))))
          (set-frame-width nil 80)
          (should (+test-wait-for (lambda () (= (frame-width) 80)) 5))
          (should (= (funcall lines (make-string 100 ?x)) 2))
          (dolist (said (+test-example-messages))
            (should (equal (list said (funcall lines (cdr said))) (list said 1)))))
      (message nil)
      (+test-e2e-frame-reset))))
