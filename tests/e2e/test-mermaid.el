;;; tests/e2e/test-mermaid.el -*- lexical-binding: t; -*-
;; Mermaid with the real mmdc (skipped where it isn't installed), in a GUI
;; Emacs: a diagram drawn in the background, in a real theme's colours, an
;; image Emacs shows (its words' spaces kept); drawn again in another theme;
;; Mermaid's own message for an error; mermaid-mode's SPC m b opening the SVG
;; in the image viewer. A run takes a second or more (node and a headless
;; Chrome): each waits up to a minute.

(+test-load "config/window" "config/mermaid")
(require 'mermaid-mode)
(require 'doom-themes)
(add-to-list 'custom-theme-load-path (file-name-directory (locate-library "doom-themes")))

;; Doom's `doom-enable-theme-h': a theme enabled runs `doom-load-theme-hook'.
(defun +test-mermaid--enabled (_theme)
  (with-temp-buffer
    (run-hooks 'doom-load-theme-hook)))
(add-hook 'enable-theme-functions #'+test-mermaid--enabled -90)

;; ====== HELPERS ======

(defun +test-mermaid--needs-mmdc ()
  (unless (executable-find +my/mermaid-mmdc)
    (ert-skip "No mmdc (npm install -g @mermaid-js/mermaid-cli)")))

(defun +test-mermaid--theme (theme)
  "THEME, the only one, as SPC h t loads it."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t))

(defun +test-mermaid--draw (source)
  "SOURCE drawn by the real mmdc: (FILE MESSAGE)."
  (let* ((result nil)
         (file (+my/mermaid-render source (lambda (file message) (setq result (list file message))))))
    (or (and file (list file nil))
        (progn (should (+test-wait-for (lambda () result) 60))
               result))))

(defun +test-mermaid--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro +test-mermaid--fresh (&rest body)
  "BODY with an empty cache, from doom-one."
  (declare (indent 0))
  `(let ((+my/mermaid-cache-directory (file-name-as-directory (make-temp-file (+test-tmp-file "mermaid/cache-") t)))
         (+my/mermaid--json nil))
     (unwind-protect
         (+test-with-reset
           (+test-mermaid--theme 'doom-one)
           ,@body)
       (mapc #'disable-theme custom-enabled-themes))))

;; ====== DRAWN ======

(ert-deftest e2e-mermaid/drawn-in-the-theme-s-colours ()
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (pcase-let ((`(,file ,message) (+test-mermaid--draw "flowchart LR\n    A[Write the code] --> B{Tests pass?}\n")))
      (should-not message)
      (let ((text (+test-mermaid--text file)))
        ;; doom-one's: its background, the keyword's blue around the nodes.
        (should (string-search (downcase (face-foreground 'font-lock-keyword-face)) (downcase text)))
        (should (string-search "xml:space=\"preserve\"" text))
        ;; SVG's own text (Emacs draws no HTML in an SVG), each word there.
        (should-not (string-search "foreignObject" text))
        (should (string-search ">Write<" text))
        (should (string-search "> the<" text)))
      ;; An image Emacs draws.
      (let ((size (image-size (create-image file 'svg) t)))
        (should (> (car size) 100))
        (should (> (cdr size) 20)))
      ;; Asked again: from the cache, at once.
      (should (equal (+my/mermaid-render "flowchart LR\n    A[Write the code] --> B{Tests pass?}\n" #'ignore)
                     file)))))

(ert-deftest e2e-mermaid/drawn-again-in-another-theme ()
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (let* ((ran 0)
           (+my/mermaid-theme-hook (list (lambda () (cl-incf ran))))
           (dark (car (+test-mermaid--draw "flowchart TD\n    A --> B\n"))))
      (+test-mermaid--theme 'doom-one-light)
      (should (= ran 1))
      (should-not (+my/mermaid-cached "flowchart TD\n    A --> B\n"))
      (let ((light (car (+test-mermaid--draw "flowchart TD\n    A --> B\n"))))
        (should-not (equal dark light))
        (should (string-search (downcase (face-foreground 'font-lock-keyword-face))
                               (downcase (+test-mermaid--text light))))))))

(ert-deftest e2e-mermaid/an-error-mermaid-s-message ()
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (pcase-let ((`(,file ,message) (+test-mermaid--draw "flowchart TD\n    A --> B -->\n    C[[\n")))
      (should-not file)
      (should (string-prefix-p "Parse error on line" message))
      (should-not (string-search "at async" message)))))

(ert-deftest e2e-mermaid/spc-m-b-opens-the-svg ()
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (let ((svg (expand-file-name "current-buffer.svg" mermaid-tmp-dir)))
      (ignore-errors (delete-file svg))
      (with-current-buffer (get-buffer-create "flow.mmd")
        (insert "sequenceDiagram\n    You->>Emacs: SPC m b\n")
        (mermaid-mode)
        (mermaid-compile-buffer))
      (should (+test-wait-for (lambda () (find-buffer-visiting svg)) 60))
      (with-current-buffer (find-buffer-visiting svg)
        (should (derived-mode-p 'image-mode))
        (should (image-get-display-property)))
      (kill-buffer "flow.mmd")
      (kill-buffer (find-buffer-visiting svg)))))
