;;; tests/e2e/test-examples.el -*- lexical-binding: t; -*-
;; The examples in a GUI Emacs: the merge example's panes on screen, its
;; wands in the Result's margin; Done, and its repository is gone. The PDF in
;; PDF.js, dark; the Markdown preview loaded; the drawing in Excalidraw; the
;; error stripe's frame shown; the notices' frame: each ready (what the
;; screenshots wait for), and its files gone once closed. PDF.js and
;; Excalidraw: copies of Doom's, never downloaded here.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/childframe" "config/banner" "config/window" "config/tabs" "config/editor" "config/long-lines"
            "config/actions" "config/webkit" "config/pdf" "config/markdown" "config/excalidraw" "config/stripe"
            "config/tiling" "config/merge" "config/examples")
(global-tab-line-mode 1)
(global-so-long-mode 1)
(setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css"))

(defvar +test-examples--pdfjs (+test-pdfjs-dir))
(defvar +test-examples--excalidraw (+test-excalidraw-dir))

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

(ert-deftest e2e-examples/markdown-and-its-preview ()
  "The README, its preview beside it, loaded; closed: the preview with it,
the file gone."
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

(ert-deftest e2e-examples/drawing-in-excalidraw ()
  "The drawing up in Excalidraw, not changed (nothing to save); closed: its
file gone."
  (skip-unless +test-examples--excalidraw)
  (+test-with-reset
    (let* ((buffer (+my/example-excalidraw))
           (dir (+test-examples--folder buffer)))
      (should (+test-wait-for #'+my/example-excalidraw-ready 30))
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
                                  (and (frame-live-p frame) (frame-visible-p frame))))
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
                                  (and (frame-live-p frame) (frame-visible-p frame))))
                              10))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))
