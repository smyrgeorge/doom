;;; tests/e2e/test-mermaid.el -*- lexical-binding: t; -*-
;; Mermaid in a GUI Emacs. With the real mmdc (skipped where it isn't
;; installed): a diagram drawn in the background, in a real theme's colours,
;; an image Emacs shows (its words' spaces kept); drawn again in another
;; theme; Mermaid's own message for an error; mermaid-mode's SPC m b opening
;; the SVG in the image viewer. A run takes a second or more (node and a
;; headless Chrome): each waits up to a minute. A Mermaid file's preview in
;; WebKit (mermaid.js: Doom's, copied; skipped without it or xwidgets): drawn,
;; redrawn as you type, an error under the last drawing, re-themed, zoomed
;; (past a narrow pane, scrolled sideways). Without WebKit, mmdc's image:
;; zoomed, scrolled sideways, a tall one scrolled through.
;; ```mermaid blocks in Markdown's live preview (pandoc too): drawn, only an
;; edited one drawn again, an error in place, re-themed with the page. In a
;; reply of Claude Code's, as agent-shell renders it: drawn, copied back.
;; Agent UI's mermaid element: drawn, in a snapshot as shown.
;; run.sh: slow (~30 s beside the others: started first).

(require 'markdown-mode)
;; The Markdown preview's stylesheets (Doom's markdown module sets GitHub's).
(setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css"))
(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)
(+test-load "config/emacs" "config/banner" "config/webkit" "config/markdown"
            "config/agent-shell" "config/mermaid" "config/agent-ui")
(require 'agent-shell)

;; mermaid.js: Doom's, copied into the temp data folder.
(defvar +test-mermaid--js (+test-mermaid-js-dir))
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

;; ====== THE PREVIEW, IN WEBKIT ======

(defun +test-mermaid--page (xwidget expression)
  "EXPRESSION's value (a string) in XWIDGET's page."
  (+test-js xwidget (format "String(%s)" expression)))

(defun +test-mermaid--preview-xwidget (mmd)
  "MMD's preview's view, once its page has drawn a diagram (or an error)."
  (+test-wait-for
   (lambda ()
     (let* ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd))
            (window (and (buffer-live-p preview) (get-buffer-window preview))))
       (when window
         (with-current-buffer preview
           (let ((xwidget (+my/webkit-xwidget window)))
             (and xwidget
                  (member (+test-mermaid--page xwidget "document.title") '("mmd drawn" "mmd error"))
                  xwidget))))))
   20))

(defmacro +test-mermaid--preview (&rest body)
  "BODY with WebKit and mermaid.js there, from one window, in doom-one; the
preview and files closed after."
  (declare (indent 0))
  `(progn
     (+test-needs-webkit)
     (unless +test-mermaid--js
       (ert-skip "No mermaid.js in Doom's data folder (open a Mermaid preview once)"))
     (+test-mermaid--fresh
       (unwind-protect (progn ,@body)
         (dolist (buffer (buffer-list))
           (when (buffer-local-value '+my/mermaid-preview-mode buffer)
             (with-current-buffer buffer (+my/mermaid-preview-mode -1)))
           (when (buffer-file-name buffer)
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))))))

(ert-deftest e2e-mermaid/preview-draws-and-follows-typing ()
  (+test-mermaid--preview
    (let ((mmd (find-file (+test-file "mermaid/preview.mmd" "flowchart LR\n    A[Write the code] --> B\n"))))
      (let ((this-command '+my/mermaid-preview-toggle))
        (+my/mermaid-preview-toggle))
      (let ((xwidget (+test-mermaid--preview-xwidget mmd)))
        (should xwidget)
        (should (equal (+test-mermaid--page xwidget "document.title") "mmd drawn"))
        ;; mermaid.js's SVG, in the theme's colours.
        (should (equal (+test-mermaid--page xwidget "!!document.querySelector('#diagram svg')") "true"))
        ;; Its label's words, on one row or wrapped (WebKitGTK's text a little
        ;; wider: "Write the" over "code", which innerText joins as "Write
        ;; thecode").
        (should (string-search "Writethecode"
                               (replace-regexp-in-string
                                "[[:space:]]+" "" (+test-mermaid--page xwidget "document.body.innerText"))))
        (should (string-search (downcase (face-foreground 'font-lock-keyword-face))
                               (downcase (+test-mermaid--page xwidget "document.querySelector('#diagram svg').outerHTML"))))
        ;; The cursor stayed in the file.
        (should (eq (window-buffer (selected-window)) mmd))
        ;; Typed: drawn anew, in place (the same page).
        (with-current-buffer mmd
          (goto-char (point-max))
          (insert "    B --> C[Typed]\n"))
        (should (+test-wait-for
                 (lambda () (string-search "Typed" (+test-mermaid--page xwidget "document.body.innerText")))
                 10))
        ;; An error: Mermaid's message under the last drawing.
        (with-current-buffer mmd (insert "    C --> \n    -->\n"))
        (should (+test-wait-for (lambda () (equal (+test-mermaid--page xwidget "document.title") "mmd error")) 10))
        (should (equal (+test-mermaid--page xwidget "document.getElementById('error').hidden") "false"))
        (should (string-search "Parse error" (+test-mermaid--page xwidget "document.getElementById('error').textContent")))
        (should (string-search "Typed" (+test-mermaid--page xwidget "document.querySelector('#diagram').textContent")))
        ;; SPC m p again: closed.
        (with-current-buffer mmd
          (let ((this-command '+my/mermaid-preview-toggle))
            (+my/mermaid-preview-toggle))
          (should-not +my/mermaid-preview-mode))
        (should (= (length (window-list)) 1))))))

(ert-deftest e2e-mermaid/preview-re-themed-and-zoomed ()
  (+test-mermaid--preview
    (let ((mmd (find-file (+test-file "mermaid/theme.mmd" "flowchart LR\n    A --> B\n"))))
      (+my/mermaid-preview-show)
      (let ((xwidget (+test-mermaid--preview-xwidget mmd))
            (preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
        (should xwidget)
        (should (equal (+test-mermaid--page xwidget "getComputedStyle(document.documentElement).backgroundColor")
                       "rgb(40, 44, 52)"))
        (+test-mermaid--theme 'doom-one-light)
        (should (+test-wait-for
                 (lambda () (equal (+test-mermaid--page xwidget "getComputedStyle(document.documentElement).backgroundColor")
                                   "rgb(250, 250, 250)"))
                 10))
        ;; Its diagram drawn again, in the light theme's colours.
        (should (+test-wait-for
                 (lambda () (string-search (downcase (face-foreground 'font-lock-keyword-face))
                                           (downcase (+test-mermaid--page xwidget "document.querySelector('#diagram svg').outerHTML"))))
                 10))
        ;; Zoomed: drawn 1.5625 times as wide as it is (twice +), then back.
        (let ((natural (string-to-number (+test-mermaid--page xwidget "document.querySelector('#diagram svg').viewBox.baseVal.width")))
              (fitted (+test-mermaid--drawn-width xwidget)))
          (should (> natural 10))
          (should (< (abs (- fitted natural)) 1))
          (with-current-buffer preview
            (+my/mermaid-preview-zoom-in)
            (+my/mermaid-preview-zoom-in))
          (should (+test-mermaid--drawn-p xwidget (* fitted 1.5625)))
          (with-current-buffer preview (+my/mermaid-preview-zoom-reset))
          (should (+test-mermaid--drawn-p xwidget fitted)))))))

(defun +test-mermaid--drawn-width (xwidget)
  "The width XWIDGET's diagram is drawn at, in pixels (not its style's)."
  (string-to-number (+test-mermaid--page xwidget "document.querySelector('#diagram svg').getBoundingClientRect().width")))

(defun +test-mermaid--drawn-p (xwidget width)
  "Non-nil once XWIDGET's diagram is drawn WIDTH pixels wide (a pixel either
way), 5 s at most."
  (+test-wait-for (lambda () (< (abs (- (+test-mermaid--drawn-width xwidget) width)) 1)) 5))

(defun +test-mermaid--page-number (xwidget expression)
  (string-to-number (+test-mermaid--page xwidget expression)))

(ert-deftest e2e-mermaid/preview-zoomed-past-a-narrow-pane ()
  "A wide diagram in a 40-column pane: fitted to it; +, - drawn bigger or
smaller than fitted, the pane resized too; wider than the pane, either edge
scrolled to, h / l sideways."
  (+test-mermaid--preview
    (let ((mmd (find-file (+test-file "mermaid/wide.mmd"
                                      (concat "flowchart LR\n    "
                                              (mapconcat (lambda (n) (format "N%d[Step number %d]" n n))
                                                         (number-sequence 1 12) " --> ")
                                              "\n")))))
      (+my/mermaid-preview-show)
      (let* ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd))
             (pane (get-buffer-window preview))
             (xwidget (+test-mermaid--preview-xwidget mmd)))
        (should xwidget)
        (window-resize pane (- 40 (window-total-width pane)) t)
        (should (= (window-total-width pane) 40))
        ;; The view as wide as the pane, the diagram fitted to it.
        (should (+test-wait-for
                 (lambda () (= (+test-mermaid--page-number xwidget "innerWidth") (window-body-width pane t)))
                 5))
        (let ((natural (+test-mermaid--page-number xwidget "document.querySelector('#diagram svg').viewBox.baseVal.width"))
              (inner (+test-mermaid--page-number xwidget "innerWidth"))
              (fitted (+test-mermaid--drawn-width xwidget)))
          (should (> natural (* 3 inner)))
          (should (< 100 fitted inner))
          ;; Narrow margins in a narrow pane.
          (should (<= (+test-mermaid--page-number xwidget "document.querySelector('#diagram svg').getBoundingClientRect().left")
                      (* 0.04 inner)))
          (with-current-buffer preview
            (+my/mermaid-preview-zoom-in)
            (should (+test-mermaid--drawn-p xwidget (* fitted 1.25)))
            (+my/mermaid-preview-zoom-reset)
            (should (+test-mermaid--drawn-p xwidget fitted))
            (+my/mermaid-preview-zoom-out)
            (should (+test-mermaid--drawn-p xwidget (* fitted 0.8)))
            ;; Zoomed past the pane: its left edge, then its right one.
            (+my/mermaid-preview-zoom-reset)
            (dotimes (_ 4) (+my/mermaid-preview-zoom-in))
            (should (+test-mermaid--drawn-p xwidget (* fitted (expt 1.25 4))))
            (should (> (+test-mermaid--page-number xwidget "document.documentElement.scrollWidth") (* 2 inner)))
            (should (>= (+test-mermaid--page-number xwidget "document.querySelector('#diagram svg').getBoundingClientRect().left") 0))
            (with-selected-window pane
              (+my/webkit-scroll-right 100))
            (should (+test-wait-for (lambda () (> (+test-mermaid--page-number xwidget "scrollX") 0)) 5))
            ;; In view (a scroll is whole pixels: a fraction of one may not).
            (should (< (+test-mermaid--page-number xwidget "document.querySelector('#diagram svg').getBoundingClientRect().right")
                       (1+ inner)))
            ;; h / l: a step sideways.
            (with-selected-window pane
              (+my/webkit-scroll-left 100)
              (+my/webkit-scroll-right))
            (should (+test-wait-for (lambda () (= (+test-mermaid--page-number xwidget "scrollX") 60)) 5))
            ;; The pane wider: the zoom kept, of the new fitted width.
            (+my/mermaid-preview-zoom-reset)
            (window-resize pane 20 t)
            (should (+test-wait-for
                     (lambda () (= (+test-mermaid--page-number xwidget "innerWidth") (window-body-width pane t)))
                     5))
            (let ((wider (+test-mermaid--drawn-width xwidget)))
              (should (> wider fitted))
              (+my/mermaid-preview-zoom-in)
              (should (+test-mermaid--drawn-p xwidget (* wider 1.25)))
              (window-resize pane -20 t)
              (should (+test-mermaid--drawn-p xwidget (* fitted 1.25))))))))))

(ert-deftest e2e-mermaid/notice-opens-the-preview ()
  (+test-mermaid--preview
    (let ((mmd (find-file (+test-file "mermaid/notice.mmd" "flowchart LR\n    A --> B\n"))))
      (with-current-buffer mmd
        (should (assq 'mermaid-preview +my/banner--list))
        ;; Its button: the preview.
        (funcall (cdr (assoc "Open preview" (nth 2 (assq 'mermaid-preview +my/banner--list))))))
      (should (+test-mermaid--preview-xwidget mmd)))))

;; ====== THE PREVIEW, WITHOUT WEBKIT ======

(ert-deftest e2e-mermaid/preview-without-webkit-mmdc-s-image ()
  "Where Emacs has no WebKit: the real mmdc's SVG, an image Emacs draws."
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
      (let ((mmd (find-file (+test-file "mermaid/image.mmd" "flowchart LR\n    A[Write the code] --> B\n"))))
        (unwind-protect
            (progn
              (+my/mermaid-preview-show)
              (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
                (with-current-buffer preview
                  (should (eq major-mode '+my/mermaid-preview-image-mode)))
                (should (+test-wait-for
                         (lambda () (with-current-buffer preview
                                      (text-property-not-all (point-min) (point-max) 'display nil)))
                         60))
                (with-current-buffer preview
                  (let* ((pos (text-property-not-all (point-min) (point-max) 'display nil))
                         (size (image-size (get-text-property pos 'display) t)))
                    (should (> (car size) 50))
                    ;; At most the pane's width.
                    (should (<= (car size) (window-body-width (get-buffer-window preview) t)))))))
          (with-current-buffer mmd
            (+my/mermaid-preview-mode -1)
            (set-buffer-modified-p nil))
          (kill-buffer mmd))))))

(defmacro +test-mermaid--image-preview (name source &rest body)
  "BODY with SOURCE's preview without WebKit (the real mmdc's image), from a
Mermaid file NAME: `mmd' the file's buffer, `preview' the preview's, `pane'
its window, once drawn."
  (declare (indent 2))
  `(progn
     (+test-mermaid--needs-mmdc)
     (+test-mermaid--fresh
       (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
         (let ((mmd (find-file (+test-file (concat "mermaid/" ,name) ,source))))
           (unwind-protect
               (progn
                 (+my/mermaid-preview-show)
                 (let* ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd))
                        (pane (get-buffer-window preview)))
                   (should pane)
                   (should (+test-wait-for (lambda () (+test-mermaid--image-size preview)) 60))
                   ,@body))
             (with-current-buffer mmd
               (+my/mermaid-preview-mode -1)
               (set-buffer-modified-p nil))
             (kill-buffer mmd)))))))

(defun +test-mermaid--image-size (preview)
  "The size in pixels of the image PREVIEW shows, or nil."
  (with-current-buffer preview
    (let ((pos (text-property-not-all (point-min) (point-max) 'display nil)))
      (and pos (image-size (get-text-property pos 'display) t)))))

(defun +test-mermaid--at (pane x y)
  "What PANE shows at X, Y (pixels in its body): (POSITION OBJECT-X . OBJECT-Y),
OBJECT-X/Y in its image if it's the image's; nil past the text."
  (let ((posn (posn-at-x-y x y pane)))
    (and posn (posn-point posn)
         (cons (posn-point posn) (and (posn-image posn) (posn-object-x-y posn))))))

(ert-deftest e2e-mermaid/preview-without-webkit-zoomed-and-panned ()
  "Without WebKit, a wide diagram in a 40-column pane: fitted to it; +, -
drawn bigger or smaller than fitted, 0 fitted again; wider than the pane, h
/ l sideways, its right edge at the pane's at most; the pane wider, the zoom
kept."
  (+test-mermaid--image-preview "wide-image.mmd"
      (concat "flowchart LR\n    "
              (mapconcat (lambda (n) (format "N%d[Step number %d]" n n)) (number-sequence 1 12) " --> ")
              "\n")
    (window-resize pane (- 40 (window-total-width pane)) t)
    (+test-sleep 0.2)
    (let ((fitted (car (+test-mermaid--image-size preview)))
          (inner (window-body-width pane t)))
      (should (< 100 fitted inner))
      (with-selected-window pane
        (+my/mermaid-preview-zoom-in)
        (should (= (car (+test-mermaid--image-size preview)) (round (* 1.25 fitted))))
        (+my/mermaid-preview-zoom-reset)
        (should (= (car (+test-mermaid--image-size preview)) fitted))
        (+my/mermaid-preview-zoom-out)
        (should (= (car (+test-mermaid--image-size preview)) (round (* 0.8 fitted))))
        (+my/mermaid-preview-zoom-reset)
        ;; Zoomed past the pane: scrolled sideways, a step, then its right
        ;; edge at the pane's, no further; back.
        (dotimes (_ 4) (+my/mermaid-preview-zoom-in))
        (let ((width (car (+test-mermaid--image-size preview))))
          (should (> width (* 2 inner)))
          (should (= (window-hscroll pane) 0))
          (+my/mermaid-preview-image-right)
          (+test-sleep 0.1)
          (should (= (window-hscroll pane) (round +my/webkit-scroll-step (frame-char-width))))
          (+my/mermaid-preview-image-right 100)
          (+test-sleep 0.1)
          ;; Its right edge in the pane's last column (its middle row: under
          ;; the empty line above it).
          (let* ((column (frame-char-width))
                 (middle (+ (frame-char-height) (/ (cdr (+test-mermaid--image-size preview)) 2)))
                 (right (+test-mermaid--at pane (- inner column 1) middle))
                 (most (window-hscroll pane)))
            (should (cdr right))
            (should (<= (- width column 1) (cadr right) (1- width)))
            (+my/mermaid-preview-image-right)
            (should (= (window-hscroll pane) most)))
          (+my/mermaid-preview-image-left 100)
          (+test-sleep 0.1)
          (should (= (window-hscroll pane) 0))))
      ;; The pane wider: the zoom kept, of the new fitted width.
      (with-selected-window pane (+my/mermaid-preview-zoom-reset))
      (window-resize pane 20 t)
      (+test-sleep 0.2)
      (let ((wider (car (+test-mermaid--image-size preview))))
        (should (> wider fitted))
        (with-selected-window pane (+my/mermaid-preview-zoom-in))
        (should (= (car (+test-mermaid--image-size preview)) (round (* 1.25 wider))))
        (window-resize pane -20 t)
        (+test-sleep 0.2)
        (should (= (car (+test-mermaid--image-size preview)) (round (* 1.25 fitted))))))))

(ert-deftest e2e-mermaid/preview-without-webkit-a-tall-diagram-scrolled ()
  "Without WebKit, a diagram taller than its pane: j / k, C-d, G, gg scroll
through it in pixels, the pane never blank: at G its bottom at the pane's
bottom, no further."
  (+test-mermaid--image-preview "tall-image.mmd"
      (concat "flowchart TD\n    "
              (mapconcat (lambda (n) (format "N%d[Step %d]" n n)) (number-sequence 1 24) " --> ")
              "\n")
    (let* ((height (cdr (+test-mermaid--image-size preview)))
           (body (window-body-height pane t))
           (y (lambda () (with-current-buffer preview (+my/mermaid-preview--y pane))))
           (full (lambda ()
                   ;; The image at the pane's top and bottom: no blank.
                   (+test-sleep 0.1)
                   (let ((top (+test-mermaid--at pane 10 1))
                         (bottom (+test-mermaid--at pane 10 (- body 2))))
                     (and (cdr top) (cdr bottom) (list (cddr top) (cddr bottom)))))))
      (should (> height (* 2 body)))
      (with-selected-window pane
        (+my/mermaid-preview-image-down 2)
        (should (= (funcall y) (* 2 +my/webkit-scroll-step)))
        (should (funcall full))
        (+my/mermaid-preview-image-up)
        (should (= (funcall y) +my/webkit-scroll-step))
        (+my/mermaid-preview-image-half-screen-down)
        (should (= (funcall y) (+ +my/webkit-scroll-step (/ body 2))))
        (should (funcall full))
        ;; G: the image's bottom at the pane's (the line above it, empty, at
        ;; the top of the text: scrolled by its height more).
        (+my/mermaid-preview-image-bottom)
        (let ((most (funcall y)))
          (should (> most (- height body)))
          (let ((rows (funcall full)))
            (should rows)
            (should (<= (- height 4) (cadr rows) (1- height))))
          (+my/mermaid-preview-image-down 10)
          (should (= (funcall y) most))
          (should (funcall full))
          (+my/mermaid-preview-image-up)
          (should (= (funcall y) (- most +my/webkit-scroll-step))))
        (+my/mermaid-preview-image-top)
        (should (= (funcall y) 0))
        (+test-sleep 0.1)
        (should (= (window-start pane) (with-current-buffer preview (point-min))))))))

;; ====== IN MARKDOWN'S PREVIEW ======

(defun +test-mermaid--md-xwidget (md)
  "MD's Markdown preview's view, once its page has drawn its diagrams."
  (+test-wait-for
   (lambda ()
     (let* ((preview (buffer-local-value '+md-preview--buffer md))
            (window (and (buffer-live-p preview) (get-buffer-window preview))))
       (when window
         (with-current-buffer preview
           (let ((xwidget (+my/webkit-xwidget window)))
             (and xwidget
                  (equal (+test-mermaid--page
                          xwidget "document.querySelectorAll('div.mermaid-diagram svg').length")
                         "2")
                  xwidget))))))
   20))

(ert-deftest e2e-mermaid/markdown-preview-draws-its-blocks ()
  (+test-mermaid--preview
    (unless (executable-find "pandoc") (ert-skip "No pandoc"))
    (let ((md (find-file (+test-file "mermaid/doc.md"
                                     (concat "# Diagrams\n\n```mermaid\nflowchart LR\n    A[First] --> B\n```\n\n"
                                             "Between.\n\n```mermaid\nsequenceDiagram\n    You->>Emacs: Second\n```\n")))))
      (markdown-mode)
      (let ((this-command '+my/markdown-preview-toggle))
        (+my/markdown-preview-toggle))
      (let ((xwidget (+test-mermaid--md-xwidget md))
            (preview (buffer-local-value '+md-preview--buffer md)))
        (should xwidget)
        (should (string-search "First" (+test-mermaid--page xwidget "document.body.innerText")))
        (should (string-search "Second" (+test-mermaid--page xwidget "document.body.innerText")))
        ;; The theme's colours, the scroll's source lines kept.
        (should (string-search (downcase (face-foreground 'font-lock-keyword-face))
                               (downcase (+test-mermaid--page xwidget "document.querySelector('div.mermaid-diagram svg').outerHTML"))))
        (should (equal (+test-mermaid--page xwidget "document.querySelector('div.mermaid-diagram').getAttribute('data-pos')")
                       "3:1-7:1"))
        ;; One block edited: only it is drawn again.
        (+test-mermaid--page xwidget "(window.renders = 0, (function(r){ mermaid.render = function(){ renders++; return r.apply(this, arguments); }; })(mermaid.render), 0)")
        (with-current-buffer md
          (goto-char (point-min))
          (search-forward "A[First]")
          (replace-match "A[Edited]"))
        (should (+test-wait-for
                 (lambda () (string-search "Edited" (+test-mermaid--page xwidget "document.body.innerText")))
                 10))
        (should (equal (+test-mermaid--page xwidget "window.renders") "1"))
        (should (string-search "Second" (+test-mermaid--page xwidget "document.body.innerText")))
        ;; An error: Mermaid's message in place, its last drawing kept.
        (with-current-buffer md
          (search-forward "-->")
          (replace-match "--> -->"))
        (should (+test-wait-for
                 (lambda () (string-search "Parse error"
                                           (+test-mermaid--page xwidget "(document.querySelector('.mermaid-error') || {}).textContent")))
                 10))
        (should (string-search "Edited" (+test-mermaid--page xwidget "document.querySelector('div.mermaid-diagram').textContent")))
        ;; Re-themed with the page.
        (with-current-buffer md
          (search-backward "--> -->")
          (replace-match "-->"))
        (should (+test-wait-for
                 (lambda () (equal (+test-mermaid--page xwidget "document.querySelectorAll('.mermaid-error').length") "0"))
                 10))
        (+test-mermaid--theme 'doom-one-light)
        (with-current-buffer preview
          (should (+test-wait-for
                   (lambda () (string-search (downcase (face-foreground 'font-lock-keyword-face))
                                             (downcase (+test-mermaid--page xwidget "document.querySelector('div.mermaid-diagram svg').outerHTML"))))
                   10)))
        (with-current-buffer md (+md-preview-mode -1))))))

;; ====== IN CLAUDE CODE'S REPLIES ======

(ert-deftest e2e-mermaid/a-reply-s-diagram ()
  "A reply rendered as agent-shell renders it: its block drawn by the real
mmdc, an image Emacs draws, as wide as the window at most; copied, the reply
as it came."
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (let ((reply "Here:\n\n```mermaid\nsequenceDiagram\n    You->>Emacs: a reply\n```\n\nDone.\n"))
      (with-current-buffer (get-buffer-create "*reply*")
        (switch-to-buffer (current-buffer))
        (unwind-protect
            (progn
              (insert reply)
              (agent-shell-markdown-replace-markup)
              (should (+test-wait-for
                       (lambda () (when-let* ((region (car (+my/agent-shell-mermaid--regions))))
                                    (eq (car-safe (get-text-property (car region) 'display)) 'image)))
                       60))
              (let* ((region (car (+my/agent-shell-mermaid--regions)))
                     (size (image-size (get-text-property (car region) 'display) t)))
                (should (> (car size) 100))
                (should (<= (car size) (window-body-width nil t))))
              (should (equal (agent-shell-markdown-reconstruct (point-min) (point-max)) reply)))
          (kill-buffer))))))

;; ====== ON AGENT UI'S CANVAS ======

(ert-deftest e2e-mermaid/an-agent-ui-element-and-its-snapshot ()
  (+test-mermaid--needs-mmdc)
  (+test-mermaid--fresh
    (let* ((element '(:type "mermaid" :id "flow" :diagram "flowchart LR\n    build --> test --> deploy"))
           (ctx (agent-ui-context :width 60 :graphic t :char-width (frame-char-width) :line-height (frame-char-height)))
           (drawn nil))
      (cl-letf (((symbol-function 'agent-ui-mermaid--redraw) (lambda (&rest _) (setq drawn t))))
        (agent-ui-render element ctx)
        (should (+test-wait-for (lambda () drawn) 60)))
      (let* ((text (agent-ui-render element ctx))
             (pos (text-property-not-all 0 (length text) 'display nil text))
             (image (get-text-property pos 'display text))
             (size (image-size image t)))
        ;; An image Emacs draws, at most the canvas's width.
        (should (> (car size) 100))
        (should (<= (car size) (* (frame-char-width) 60)))
        ;; Its snapshot: the diagram nested, as shown.
        (let ((svg (agent-ui-snapshot-svg text ctx)))
          (should (string-search ">build<" svg))
          (should (string-match-p "<svg x=\"[0-9]+\" y=\"[0-9]+\" width=\"[0-9]+\" height=\"[0-9]+\"" svg)))))))
