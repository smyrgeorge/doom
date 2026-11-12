;;; tests/unit/test-mermaid.el -*- lexical-binding: t; -*-
;; config/mermaid.el: Mermaid files in mermaid-mode (highlighted, indented),
;; its commands on SPC m keys, drawing SVGs in Doom's cache in the theme's
;; colours; ```mermaid blocks highlighted in Markdown and agent-shell; Org's
;; mermaid blocks. Mermaid's config from the theme's faces (a stand-in theme:
;; faces' colours faked), its file, a theme switch; no colour in the code.
;; The renderer, the preview. mmdc is a stand-in (tests/helper-mermaid.el).

(require 'json)
(require 'xwidget)                      ; before faking its functions
(+test-load "config/window" "config/webkit" "config/mermaid")
(require 'mermaid-mode)
(load (expand-file-name "../helper-mermaid" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defun +test-mermaid--variables ()
  "The config's theme variables, as an alist."
  (alist-get 'themeVariables (+my/mermaid-config)))

(defun +test-mermaid--blend (colour background amount)
  "COLOUR blended into BACKGROUND, worked out here: AMOUNT of COLOUR."
  (apply #'format "#%02x%02x%02x"
         (cl-mapcar (lambda (a b) (round (+ (* amount a) (* (- 1 amount) b))))
                    (mapcar (lambda (v) (/ v 257)) (color-values-from-color-spec colour))
                    (mapcar (lambda (v) (/ v 257)) (color-values-from-color-spec background)))))

(defun +test-mermaid--near (a b)
  "A and B, two #rrggbb, the same but for rounding."
  (seq-every-p (lambda (pair) (<= (abs (- (car pair) (cdr pair))) 257))
               (cl-mapcar #'cons (color-values-from-color-spec a) (color-values-from-color-spec b))))

;; ====== MERMAID FILES ======

(ert-deftest mermaid/files-open-in-mermaid-mode ()
  (dolist (name '("flow.mmd" "flow.mermaid"))
    (let ((buffer (find-file-noselect (+test-file (concat "mermaid/" name) "flowchart TD\n    A --> B\n"))))
      (unwind-protect
          (with-current-buffer buffer
            (should (eq major-mode 'mermaid-mode)))
        (kill-buffer buffer)))))

(ert-deftest mermaid/highlighted ()
  (with-temp-buffer
    (insert "flowchart TD\n    A --> B\n    %% a comment\n")
    (mermaid-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (eq (get-text-property (point) 'face) 'font-lock-keyword-face))
    (search-forward "-->")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-function-name-face))
    (search-forward "%%")
    (should (memq (get-text-property (point) 'face) '(font-lock-comment-face font-lock-comment-delimiter-face)))))

(ert-deftest mermaid/tab-indents ()
  (with-temp-buffer
    (insert "flowchart TD\nA --> B\nsubgraph one\nC --> D\nend\n")
    (mermaid-mode)
    (setq-local indent-tabs-mode nil)     ; Doom's
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   "flowchart TD\n    A --> B\n    subgraph one\n        C --> D\n    end\n"))
    ;; TAB in insert state: the line's indentation.
    (goto-char (point-min))
    (forward-line 1)
    (delete-horizontal-space)
    (should (eq indent-line-function 'mermaid-indent-line))
    (indent-for-tab-command)
    (should (= (current-indentation) 4))))

(ert-deftest mermaid/settings ()
  (should (equal mermaid-output-format ".svg"))
  (should (file-in-directory-p mermaid-tmp-dir doom-cache-dir))
  (should (string-suffix-p "/" mermaid-tmp-dir))
  (should (file-in-directory-p +my/mermaid-config-file doom-cache-dir))
  ;; Its commands draw in the theme's colours, on no background.
  (should (equal (split-string mermaid-flags " " t)
                 (list "-c" +my/mermaid-config-file "-b" "transparent"))))

;; ====== ITS COMMANDS ======
;; Through the renderer: Emacs doesn't wait, the SVG opened once drawn.

(defun +test-mermaid--shown-file (shown)
  "The file of the buffer the commands showed last (SHOWN's first)."
  (and shown (buffer-file-name (get-buffer (car shown)))))

(ert-deftest mermaid/draw-the-buffer ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (with-temp-buffer
        (insert "flowchart TD\n    A --> B\n")
        (mermaid-mode)
        (mermaid-compile-buffer)
        ;; Nothing waited for.
        (should-not shown))
      (should (+test-mermaid--wait (lambda () shown)))
      (let ((args (car (+test-mermaid--runs mmdc)))
            (svg (+test-mermaid--shown-file shown)))
        ;; The theme's config given, the source on mmdc's input.
        (should (equal (+test-mermaid--arg args "-c") +my/mermaid-config-file))
        (should (equal (+test-mermaid--arg args "-b") "transparent"))
        (should (equal (+test-mermaid--arg args "-i") "-"))
        ;; The buffer's SVG in Doom's cache.
        (should (equal svg (expand-file-name "current-buffer.svg" mermaid-tmp-dir)))
        (should (string-match-p "<desc>flowchart TD\n    A --> B\n*</desc>" (+test-mermaid--text svg)))
        (should (string-search (+my/mermaid-config-json) (+test-mermaid--text svg)))))))

(ert-deftest mermaid/draw-the-region ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (with-temp-buffer
        (insert "%% not this\nflowchart TD\n    A --> B\n")
        (mermaid-mode)
        (transient-mark-mode 1)
        (goto-char (point-min))
        (forward-line 1)
        (push-mark (point) t t)
        (goto-char (point-max))
        (mermaid-compile-region))
      (should (+test-mermaid--wait (lambda () shown)))
      (let ((text (+test-mermaid--text (+test-mermaid--shown-file shown))))
        (should (string-search "flowchart TD" text))
        (should-not (string-search "not this" text))))))

(ert-deftest mermaid/draw-the-file-next-to-it ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((file (+test-file "mermaid/next/flow.mmd" "flowchart TD\n    A --> B\n")))
        (with-temp-buffer
          (insert-file-contents file)
          (setq buffer-file-name file)
          (mermaid-mode)
          (mermaid-compile)
          (set-buffer-modified-p nil))
        (should (+test-mermaid--wait (lambda () shown)))
        (should (equal (+test-mermaid--shown-file shown) (concat (file-name-sans-extension file) ".svg")))
        ;; Its words' spaces kept (Emacs's SVG library dropped them).
        (should (string-prefix-p "<svg xml:space=\"preserve\" id=\"my-svg\""
                                 (+test-mermaid--text (+test-mermaid--shown-file shown))))
        ;; Again: from the cache, shown at once, the open SVG shown anew.
        (setq shown nil)
        (with-temp-buffer
          (insert-file-contents file)
          (setq buffer-file-name file)
          (mermaid-mode)
          (mermaid-compile)
          (set-buffer-modified-p nil))
        (should shown)
        (should (= (length (+test-mermaid--runs mmdc)) 1))))))

(ert-deftest mermaid/draw-in-the-new-theme ()
  "A command run after a theme switch draws in the new theme's colours."
  (+test-mermaid--with-mmdc
    (with-temp-buffer
      (insert "flowchart TD\n    A --> B\n")
      (mermaid-mode)
      (+test-mermaid--theme +test-mermaid--dark
        (mermaid-compile-buffer)
        (should (+test-mermaid--wait (lambda () shown))))
      (setq shown nil)
      (+test-mermaid--theme +test-mermaid--light
        (mermaid-compile-buffer)
        (should (+test-mermaid--wait (lambda () shown)))
        (should (= (length (+test-mermaid--runs mmdc)) 2))
        (should (string-search "\"darkMode\":false" (+test-mermaid--text (+test-mermaid--shown-file shown))))))))

(ert-deftest mermaid/draw-an-error ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (with-temp-buffer
        (insert "flowchart TD\n    A --> ERROR\n")
        (mermaid-mode)
        (mermaid-compile-buffer))
      (should (+test-mermaid--wait (lambda () shown)))
      (should (equal (car shown) "*mmdc*"))
      (should (string-prefix-p "Parse error on line 2:" (with-current-buffer "*mmdc*" (buffer-string)))))))

(ert-deftest mermaid/draw-another-format-mermaid-mode-s-way ()
  (let ((mermaid-output-format ".png")
        (ran nil))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest args) (setq ran args) 1))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (mermaid-compile-file (+test-file "mermaid/png/flow.mmd" "flowchart TD\n")))
    (should ran)))

(ert-deftest mermaid/org-blocks ()
  "Org's mermaid blocks: Doom loads mermaid-mode for them (its
org-babel-execute:mermaid), which draws in the theme's colours too."
  (should (memq #'+my/mermaid-org-babel-load-h +org-babel-load-functions))
  (should (+my/mermaid-org-babel-load-h 'mermaid))
  (should-not (+my/mermaid-org-babel-load-h 'python))
  (should (fboundp 'org-babel-execute:mermaid))
  (should (advice-member-p #'+my/mermaid-before-mmdc-a 'org-babel-execute:mermaid))
  (should (equal (alist-get :results org-babel-default-header-args:mermaid) "file"))
  ;; A block drawn: mmdc given the theme's config, its SVG made to show in Emacs.
  (let ((+my/mermaid--written nil)
        (svg (+test-tmp-file "mermaid/org/flow.svg"))
        (command nil))
    (cl-letf (((symbol-function 'org-babel-eval)
               (lambda (cmd _input)
                 (setq command cmd)
                 (with-temp-file svg (insert "<svg id=\"my-svg\"><text><tspan> the</tspan></text></svg>"))
                 "")))
      (+test-mermaid--theme +test-mermaid--dark
        (org-babel-execute:mermaid "flowchart TD\n    A --> B\n" `((:file . ,svg)))))
    (should (string-match-p (regexp-quote (concat "-c " +my/mermaid-config-file " -b transparent")) command))
    (should (file-exists-p +my/mermaid-config-file))
    (should (string-prefix-p "<svg xml:space=\"preserve\""
                             (with-temp-buffer (insert-file-contents svg) (buffer-string))))))

(ert-deftest mermaid/live-editor-and-docs ()
  (with-temp-buffer
    (insert "flowchart TD\n    A --> B\n")
    (mermaid-mode)
    (let ((+test-browsed nil))
      (mermaid-open-browser)
      (mermaid-open-doc)
      (should (= (length +test-browsed) 2))
      (should (string-match-p "mermaid-live-editor" (format "%s" (car (last +test-browsed))))))))

;; ====== KEYS ======

(defun +test-mermaid--key (key)
  (lookup-key (evil-get-auxiliary-keymap mermaid-mode-map 'normal) (kbd key)))

(ert-deftest mermaid/keys ()
  (pcase-dolist (`(,key . ,command)
                 '(("SPC m c" . mermaid-compile) ("SPC m b" . mermaid-compile-buffer)
                   ("SPC m r" . mermaid-compile-region) ("SPC m f" . mermaid-compile-file)
                   ("SPC m o" . mermaid-open-browser) ("SPC m d" . mermaid-open-doc)))
    (should (eq (+test-mermaid--key key) command)))
  ;; The region's from visual state too.
  (should (eq (lookup-key (evil-get-auxiliary-keymap mermaid-mode-map 'visual) (kbd "SPC m r"))
              #'mermaid-compile-region))
  ;; mermaid-mode's own stay.
  (should (eq (lookup-key mermaid-mode-map (kbd "C-c C-c")) #'mermaid-compile)))

;; ====== ```mermaid BLOCKS ======

(ert-deftest mermaid/blocks-in-markdown-mode ()
  (require 'markdown-mode)
  (should (eq (markdown-get-lang-mode "mermaid") 'mermaid-mode)))

(ert-deftest mermaid/blocks-in-markdown-ts-mode ()
  (require 'treesit)
  (skip-unless (and (treesit-language-available-p 'markdown) (treesit-language-available-p 'markdown-inline)))
  (require 'markdown-ts-mode)
  (with-temp-buffer
    (insert "# Flow\n\n```mermaid\nflowchart TD\n    A --> B\n```\n")
    (markdown-ts-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "flowchart")
    (let ((face (get-text-property (match-beginning 0) 'face)))
      (should (memq 'font-lock-keyword-face (ensure-list face))))))

(ert-deftest mermaid/blocks-in-agent-shell ()
  (skip-unless (require 'agent-shell-markdown nil t))
  (should (eq (agent-shell-markdown--resolve-lang-mode "mermaid") 'mermaid-mode))
  (let ((code (agent-shell-markdown--highlight-code "flowchart TD\n    A --> B" "mermaid")))
    (should (memq 'font-lock-keyword-face (ensure-list (get-text-property 0 'face code))))))

;; ====== THE THEME'S COLOURS ======

(ert-deftest mermaid/config-is-mermaid-s-base-theme ()
  (+test-mermaid--theme +test-mermaid--dark
    (let ((config (+my/mermaid-config)))
      (should (equal (alist-get 'theme config) "base"))
      ;; The classic look: the newer one's two-colour borders and glowing shadows.
      (should (equal (alist-get 'look config) "classic"))
      ;; An ER diagram's zero, white in Mermaid whatever the theme: hollow.
      (should (string-match-p "circle { fill: #282c34; }" (alist-get 'themeCSS config)))
      ;; Labels as SVG's text: Emacs draws no HTML in an SVG.
      (should (eq (alist-get 'htmlLabels config) :false))
      (should (eq (alist-get 'htmlLabels (alist-get 'flowchart config)) :false))
      ;; Valid JSON, read back the same.
      (let ((read (json-parse-string (+my/mermaid-config-json) :object-type 'alist :false-object :false)))
        (should (equal (alist-get 'theme read) "base"))
        (should (equal (alist-get 'primaryBorderColor (alist-get 'themeVariables read)) "#51afef"))))))

(ert-deftest mermaid/colours-from-the-faces ()
  (+test-mermaid--theme +test-mermaid--dark
    (let ((variables (+test-mermaid--variables)))
      (pcase-dolist (`(,variable . ,colour)
                     '((background . "#282c34") (primaryTextColor . "#bbc2cf") (textColor . "#bbc2cf")
                       (primaryBorderColor . "#51afef") (secondaryBorderColor . "#c678dd")
                       (tertiaryBorderColor . "#5b6268") (noteBorderColor . "#ecbe7b")
                       (errorTextColor . "#ff6c6b") (critBorderColor . "#ff6c6b")
                       (edgeLabelBackground . "#282c34") (pieStrokeColor . "#282c34")
                       (actorLineColor . "#5b6268") (doneTaskBorderColor . "#5b6268")
                       (altSectionBkgColor . "#282c34")))
        (should (equal (alist-get variable variables) colour)))
      ;; Fills: the colour's tint, blended into the background.
      (pcase-dolist (`(,variable ,colour ,amount)
                     '((primaryColor "#51afef" 0.18) (secondaryColor "#c678dd" 0.18)
                       (noteBkgColor "#ecbe7b" 0.18) (tertiaryColor "#bbc2cf" 0.06)
                       (doneTaskBkgColor "#5b6268" 0.5)
                       (lineColor "#bbc2cf" 0.6)))
        (should (+test-mermaid--near (alist-get variable variables)
                                     (+test-mermaid--blend colour "#282c34" amount))))
      ;; Every colour #rrggbb: Mermaid's base theme takes no other.
      (dolist (pair variables)
        (when (and (stringp (cdr pair))
                   (string-match-p "Color\\|Bkg\\|background\\|\\`pie[0-9]\\|\\`git\\|\\`cScale"
                                   (symbol-name (car pair))))
          (should (string-match-p "\\`#[0-9a-f]\\{6\\}\\'" (cdr pair))))))))

(ert-deftest mermaid/a-face-without-a-colour-takes-default-s ()
  (+test-mermaid--theme '((default :foreground "#bbc2cf" :background "#282c34"))
    (let ((variables (+test-mermaid--variables)))
      (should (equal (alist-get 'primaryBorderColor variables) "#bbc2cf"))
      (should (equal (alist-get 'noteBorderColor variables) "#bbc2cf")))))

(ert-deftest mermaid/colour-names-resolved ()
  "A colour name as #rrggbb, X's: not a terminal palette's nearest (batch
Emacs's frame is one)."
  (+test-mermaid--theme '((default :foreground "white" :background "#282c34")
                          (font-lock-keyword-face :foreground "SkyBlue"))
    (let ((variables (+test-mermaid--variables)))
      (should (equal (alist-get 'primaryBorderColor variables) "#87ceeb"))
      (should (equal (alist-get 'textColor variables) "#ffffff")))))

(ert-deftest mermaid/dark-or-light ()
  (+test-mermaid--theme +test-mermaid--dark
    (should (eq (alist-get 'darkMode (+test-mermaid--variables)) t)))
  (+test-mermaid--theme +test-mermaid--light
    (should (eq (alist-get 'darkMode (+test-mermaid--variables)) :false))
    (should (string-match-p "\"darkMode\":false" (+my/mermaid-config-json)))))

(ert-deftest mermaid/series-from-the-accents-each-once ()
  (+test-mermaid--theme +test-mermaid--dark
    (let ((variables (+test-mermaid--variables)))
      ;; keyword, string, type, function's (builtin's is the same), error...
      (should (equal (mapcar (lambda (i) (alist-get (intern (format "pie%d" i)) variables)) '(1 2 3 4 5))
                     '("#51afef" "#98be65" "#ecbe7b" "#c678dd" "#ff6c6b")))
      ;; Fewer accents than slices: round again.
      (should (equal (alist-get 'pie6 variables) "#51afef"))
      (should (equal (alist-get 'git0 variables) "#51afef"))
      (should (equal (alist-get 'gitBranchLabel0 variables) "#282c34"))
      (should (+test-mermaid--near (alist-get 'cScale0 variables) (+test-mermaid--blend "#51afef" "#282c34" 0.35)))
      (should (equal (alist-get 'cScaleLabel0 variables) "#bbc2cf"))
      (should (equal (alist-get 'plotColorPalette (alist-get 'xyChart variables))
                     "#51afef, #98be65, #ecbe7b, #c678dd, #ff6c6b")))))

(ert-deftest mermaid/no-colours-none-made-up ()
  "Faces without colours (a batch Emacs): no colour in the config, Mermaid's
own instead; never one written in the code."
  (+test-mermaid--theme nil
    (let ((variables (+test-mermaid--variables)))
      (should (assq 'darkMode variables))
      (should-not (seq-some (lambda (pair) (and (stringp (cdr pair)) (string-prefix-p "#" (cdr pair))))
                            variables))
      (should-not (assq 'xyChart variables))
      (should-not (assq 'themeCSS (+my/mermaid-config))))))

(ert-deftest mermaid/colours-from-the-frame-not-a-notice-s ()
  "The colours from the selected frame if it's graphical, else another: never
a child frame (a notice's, its own colours)."
  (let* ((main (selected-frame))
         (child 'child) (other 'other) (tty 'tty)
         (parents `((,child . ,main))))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional frame) (memq frame (list main child other))))
              ((symbol-function 'frame-parent) (lambda (&optional frame) (alist-get frame parents))))
      (should (eq (+my/mermaid--frame) main))
      (cl-letf (((symbol-function 'selected-frame) (lambda () tty))
                ((symbol-function 'frame-list) (lambda () (list tty child other))))
        (should (eq (+my/mermaid--frame) other))))))

(ert-deftest mermaid/font-from-the-default-face ()
  (let ((face-attribute-fn (symbol-function 'face-attribute)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'face-font) (lambda (&rest _) "the-font"))
              ((symbol-function 'font-info) (lambda (&rest _) (vector "the-font" nil 13)))
              ((symbol-function 'face-attribute)
               (lambda (face attribute &rest args)
                 (if (and (eq face 'default) (eq attribute :family))
                     "JetBrains Mono"
                   (apply face-attribute-fn face attribute args)))))
      (+test-mermaid--theme +test-mermaid--dark
        (let ((variables (+test-mermaid--variables)))
          (should (equal (alist-get 'fontFamily variables) "\"JetBrains Mono\", monospace"))
          (should (equal (alist-get 'fontSize variables) "13px")))))))

;; ====== ITS FILE, A THEME SWITCH ======

(defun +test-mermaid--file-text ()
  (with-temp-buffer (insert-file-contents +my/mermaid-config-file) (buffer-string)))

(ert-deftest mermaid/config-file-written-when-it-changed ()
  (let ((+my/mermaid--written nil)
        (writes 0)
        (write-region-fn (symbol-function 'write-region)))
    (ignore-errors (delete-file +my/mermaid-config-file))
    (cl-letf (((symbol-function 'write-region)
               (lambda (&rest args) (cl-incf writes) (apply write-region-fn args))))
      (+test-mermaid--theme +test-mermaid--dark
        (should (equal (+my/mermaid-write-config) +my/mermaid-config-file))
        (should (equal (+test-mermaid--file-text) (+my/mermaid-config-json)))
        (+my/mermaid-write-config)
        (should (= writes 1)))
      ;; Gone (the cache emptied): written again.
      (delete-file +my/mermaid-config-file)
      (+test-mermaid--theme +test-mermaid--dark (+my/mermaid-write-config))
      (should (= writes 2))
      (+test-mermaid--theme +test-mermaid--light
        (+my/mermaid-write-config)
        (should (= writes 3))
        (should (equal (+test-mermaid--file-text) (+my/mermaid-config-json)))))))

(ert-deftest mermaid/theme-switch-rewrites-the-file-and-runs-the-hook ()
  (let ((+my/mermaid--written nil)
        (+my/mermaid--json nil)
        (ran 0))
    (let ((+my/mermaid-theme-hook (list (lambda () (cl-incf ran)))))
      (should (memq #'+my/mermaid-theme-h doom-load-theme-hook))
      ;; Its config made, then the same theme loaded again: nothing changed,
      ;; nothing run.
      (+test-mermaid--theme +test-mermaid--dark
        (+my/mermaid-write-config)
        (+my/mermaid-theme-h))
      (should (= ran 0))
      (+test-mermaid--theme +test-mermaid--light
        (+my/mermaid-theme-h)
        (should (= ran 1))
        (should (equal (+test-mermaid--file-text) (+my/mermaid-config-json)))
        (should (equal (+my/mermaid-theme-json) (+my/mermaid-config-json)))
        (+my/mermaid-theme-h)
        (should (= ran 1))))))

(ert-deftest mermaid/theme-switch-writes-nothing-before-mermaid-is-used ()
  (let ((+my/mermaid--written nil)
        (+my/mermaid--json nil)
        (+my/mermaid-theme-hook nil))
    (ignore-errors (delete-file +my/mermaid-config-file))
    (+test-mermaid--theme +test-mermaid--dark (+my/mermaid-theme-h))
    (should-not (file-exists-p +my/mermaid-config-file))))

;; ====== THE RENDERER ======

(defun +test-mermaid--render (source)
  "Render SOURCE: (FILE . RESULTS), FILE what it returned (drawn already),
RESULTS a list the callback pushes (FILE MESSAGE) on."
  (let* ((results (list nil))
         (file (+my/mermaid-render source (lambda (file message)
                                            (push (list file message) (car results))))))
    (cons file results)))

(ert-deftest mermaid/render-draws-in-the-background ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let* ((start (float-time))
             (asked (+test-mermaid--render "flowchart TD\n    A --> B\n"))
             (results (cdr asked)))
        ;; Not drawn yet: nothing returned, the callback later; Emacs didn't wait.
        (should-not (car asked))
        (should-not (car results))
        (should (< (- (float-time) start) 0.5))
        (should (+test-mermaid--wait (lambda () (car results))))
        (pcase-let ((`(,file ,message) (caar results)))
          (should-not message)
          (should (file-in-directory-p file +my/mermaid-cache-directory))
          (should (string-suffix-p ".svg" file))
          (let ((text (+test-mermaid--text file)))
            (should (string-prefix-p "<svg xml:space=\"preserve\"" text))
            (should (string-search "<desc>flowchart TD\n    A --> B" text))
            ;; The theme's config given.
            (should (string-search (+my/mermaid-config-json) text))))
        ;; Its part file gone.
        (should-not (directory-files +my/mermaid-cache-directory nil "\\.part\\."))
        (should (= +my/mermaid--running 0))))))

(ert-deftest mermaid/render-from-the-cache ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((results (cdr (+test-mermaid--render "flowchart TD\n    A --> B\n"))))
        (should (+test-mermaid--wait (lambda () (car results))))
        (let ((again (+test-mermaid--render "flowchart TD\n    A --> B\n")))
          ;; Its file at once, the callback not called.
          (should (equal (car again) (car (caar results))))
          (should (equal (+my/mermaid-cached "flowchart TD\n    A --> B\n") (car again)))
          (accept-process-output nil 0.1)
          (should-not (car (cdr again))))
        (should (= (length (+test-mermaid--runs mmdc)) 1))
        (should-not (+my/mermaid-cached "flowchart TD\n    C --> D\n"))))))

(ert-deftest mermaid/render-again-in-a-new-theme ()
  (+test-mermaid--with-mmdc
    (let (dark light)
      (+test-mermaid--theme +test-mermaid--dark
        (let ((results (cdr (+test-mermaid--render "flowchart TD\n"))))
          (should (+test-mermaid--wait (lambda () (car results))))
          (setq dark (car (caar results)))))
      (+test-mermaid--theme +test-mermaid--light
        (should-not (+my/mermaid-cached "flowchart TD\n"))
        (let ((results (cdr (+test-mermaid--render "flowchart TD\n"))))
          (should (+test-mermaid--wait (lambda () (car results))))
          (setq light (car (caar results)))))
      (should-not (equal dark light))
      (should (= (length (+test-mermaid--runs mmdc)) 2))
      (should (string-search "\"darkMode\":false" (+test-mermaid--text light))))))

(ert-deftest mermaid/render-the-same-diagram-once ()
  "Asked again while it's drawn: one run, each callback called."
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((first (cdr (+test-mermaid--render "flowchart TD\n")))
            (second (cdr (+test-mermaid--render "flowchart TD\n"))))
        (should (+test-mermaid--wait (lambda () (and (car first) (car second)))))
        (should (equal (caar first) (caar second)))
        (should (= (length (+test-mermaid--runs mmdc)) 1))))))

(ert-deftest mermaid/render-a-few-at-once ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let* ((+my/mermaid-jobs 1)
             (all (mapcar (lambda (n) (cdr (+test-mermaid--render (format "flowchart TD\n    A%d\n" n))))
                          '(1 2 3))))
        (should (= +my/mermaid--running 1))
        (should (= (length +my/mermaid--queue) 2))
        (should (+test-mermaid--wait (lambda () (seq-every-p #'car all))))
        (should (seq-every-p (lambda (results) (car (caar results))) all))
        (should (= (length (+test-mermaid--runs mmdc)) 3))
        (should (= +my/mermaid--running 0))))))

(ert-deftest mermaid/render-an-error-mermaid-s-message ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((results (cdr (+test-mermaid--render "flowchart TD\n    A --> ERROR\n"))))
        (should (+test-mermaid--wait (lambda () (car results))))
        (pcase-let ((`(,file ,message) (caar results)))
          (should-not file)
          ;; Mermaid's lines, not "Error: ", nor the stack trace.
          (should (equal message "Parse error on line 2:\n...A --> ERROR\nExpecting 'SEMI', got 'NODE_STRING'")))
        ;; Not cached: asked again, drawn again.
        (should-not (+my/mermaid-cached "flowchart TD\n    A --> ERROR\n"))
        (should-not (directory-files +my/mermaid-cache-directory nil "\\.svg\\'"))))))

(ert-deftest mermaid/render-without-mmdc-what-to-install ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let* ((+my/mermaid-mmdc (expand-file-name "no-such-mmdc" +test-tmp))
             (results (cdr (+test-mermaid--render "flowchart TD\n"))))
        ;; Later, as when drawn: a caller has one way to wait.
        (should-not (car results))
        (should (+test-mermaid--wait (lambda () (car results))))
        (pcase-let ((`(,file ,message) (caar results)))
          (should-not file)
          (should (string-match-p "need mmdc: npm install -g @mermaid-js/mermaid-cli" message)))))))

(ert-deftest mermaid/render-stopped-when-it-takes-too-long ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let* ((+my/mermaid-timeout 0.3)
             (results (cdr (+test-mermaid--render "flowchart TD\n    SLOW\n"))))
        (should (+test-mermaid--wait (lambda () (car results)) 2))
        (should (string-match-p "longer than 0.3 s" (cadr (caar results))))
        (should (= +my/mermaid--running 0))))))

(defun +test-mermaid--puppeteer (args)
  "The puppeteer config mmdc's ARGS name (-p), read; nil without one."
  (when-let* ((file (+test-mermaid--arg args "-p")))
    (json-parse-string (+test-mermaid--text file) :object-type 'alist :array-type 'list)))

(ert-deftest mermaid/render-as-root-without-chrome-s-sandbox ()
  (+test-mermaid--with-mmdc
    (let ((+my/mermaid-chrome nil)
          (system-type 'darwin))
      (cl-letf (((symbol-function 'user-uid) (lambda () 0)))
        (should (equal (+test-mermaid--puppeteer (+my/mermaid--arguments "out.svg"))
                       '((args "--no-sandbox")))))
      (cl-letf (((symbol-function 'user-uid) (lambda () 501)))
        (should-not (member "-p" (+my/mermaid--arguments "out.svg")))))))

(ert-deftest mermaid/render-on-linux-on-arm-with-chromium ()
  "Chrome's headless shell has no Linux ARM build: the system's chromium."
  (+test-mermaid--with-mmdc
    (let ((+my/mermaid-chrome nil)
          (system-type 'gnu/linux)
          (system-configuration "aarch64-unknown-linux-gnu"))
      (cl-letf (((symbol-function 'user-uid) (lambda () 1000))
                ((symbol-function 'executable-find)
                 (lambda (name &rest _) (and (equal name "chromium") "/usr/bin/chromium"))))
        (should (equal (+test-mermaid--puppeteer (+my/mermaid--arguments "out.svg"))
                       '((executablePath . "/usr/bin/chromium"))))
        ;; Elsewhere (Linux on x86), puppeteer's own.
        (let ((system-configuration "x86_64-pc-linux-gnu"))
          (should-not (member "-p" (+my/mermaid--arguments "out.svg"))))
        ;; One given in config.el: that one.
        (let ((+my/mermaid-chrome "/opt/chrome/chrome")
              (system-configuration "x86_64-pc-linux-gnu"))
          (should (equal (+test-mermaid--puppeteer (+my/mermaid--arguments "out.svg"))
                         '((executablePath . "/opt/chrome/chrome")))))))))

(ert-deftest mermaid/render-prunes-the-cache-once-a-session ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((+my/mermaid--pruned nil)
            (old (expand-file-name "old.svg" +my/mermaid-cache-directory))
            (recent (expand-file-name "recent.svg" +my/mermaid-cache-directory)))
        (write-region "<svg/>" nil old nil 'silent)
        (write-region "<svg/>" nil recent nil 'silent)
        (set-file-times old (time-subtract nil (days-to-time (1+ +my/mermaid-cache-days))))
        (set-file-times recent (time-subtract nil (days-to-time (1- +my/mermaid-cache-days))))
        (let ((results (cdr (+test-mermaid--render "flowchart TD\n"))))
          (should (+test-mermaid--wait (lambda () (car results)))))
        (should-not (file-exists-p old))
        (should (file-exists-p recent))
        (should +my/mermaid--pruned)))))

(ert-deftest mermaid/render-a-used-diagram-kept ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((results (cdr (+test-mermaid--render "flowchart TD\n"))))
        (should (+test-mermaid--wait (lambda () (car results))))
        (let ((file (car (caar results))))
          (set-file-times file (time-subtract nil (days-to-time 20)))
          (should (+my/mermaid-cached "flowchart TD\n"))
          (should (< (float-time (time-subtract nil (file-attribute-modification-time (file-attributes file))))
                     60)))))))

(ert-deftest mermaid/render-a-failing-callback-spares-the-others ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--with-mmdc
      (let ((got nil))
        (+my/mermaid-render "flowchart TD\n" (lambda (&rest _) (error "Broken")))
        (+my/mermaid-render "flowchart TD\n" (lambda (file _) (setq got file)))
        (let ((inhibit-message t))
          (should (+test-mermaid--wait (lambda () got))))))))

;; ====== THE PREVIEW ======
;; WebKit faked, as tests/unit/test-markdown.el does: views made, scripts
;; recorded; notices recorded. mermaid.js not downloaded (said to be there).

(cl-defstruct (+test-mermaid--xw (:constructor +test-mermaid--xw-new) (:copier nil))
  "A fake WebKit view."
  buffer props uri killed)

(defvar +test-mermaid--made nil "The fake views made, oldest first.")
(defvar +test-mermaid--scripts nil "(XWIDGET SCRIPT) run, oldest first.")
(defvar +test-mermaid--notices nil "(ID TEXT ACTIONS BUFFER) shown, latest first.")

(defmacro +test-mermaid--with-webkit (&rest body)
  "BODY with WebKit faked and working (`+my/webkit-p' t), mermaid.js there,
notices recorded, a stand-in theme, temp files in the test's folder; from one
window on *scratch*, and again after."
  (declare (indent 0))
  `(let ((+test-mermaid--made nil)
         (+test-mermaid--scripts nil)
         (+test-mermaid--notices nil)
         (temporary-file-directory
          (file-name-as-directory (make-temp-file (expand-file-name "tmp" (+test-tmp-file "dirs/")) t)))
         (+my/webkit--watch-timer nil)
         (+my/webkit--tidy-timer nil)
         (+my/mermaid-preview-notice t)
         (+my/focus-new-windows t)
         (this-command 'test))
     (cl-letf (((symbol-function 'make-xwidget)
                (lambda (_type _title _width _height &optional _arguments buffer _related)
                  (let ((xw (+test-mermaid--xw-new :buffer buffer)))
                    (setq +test-mermaid--made (append +test-mermaid--made (list xw)))
                    xw)))
               ((symbol-function 'xwidget-put)
                (lambda (xw property value)
                  (setf (+test-mermaid--xw-props xw) (plist-put (+test-mermaid--xw-props xw) property value))
                  value))
               ((symbol-function 'xwidget-get)
                (lambda (xw property) (plist-get (+test-mermaid--xw-props xw) property)))
               ((symbol-function 'xwidget-live-p) #'+test-mermaid--xw-p)
               ((symbol-function 'kill-xwidget) (lambda (xw) (setf (+test-mermaid--xw-killed xw) t)))
               ((symbol-function 'xwidget-buffer) #'+test-mermaid--xw-buffer)
               ((symbol-function 'set-xwidget-buffer)
                (lambda (xw buffer) (setf (+test-mermaid--xw-buffer xw) buffer)))
               ((symbol-function 'set-xwidget-query-on-exit-flag) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-uri)
                (lambda (xw uri) (setf (+test-mermaid--xw-uri xw) uri)))
               ((symbol-function 'xwidget-webkit-uri) #'+test-mermaid--xw-uri)
               ((symbol-function 'xwidget-webkit-title) (lambda (_xw) ""))
               ((symbol-function 'xwidget-webkit-execute-script)
                (lambda (xw script &optional _callback)
                  (setq +test-mermaid--scripts (append +test-mermaid--scripts (list (list xw script))))))
               ((symbol-function 'xwidget-webkit-adjust-size-to-window) #'ignore)
               ((symbol-function 'xwidget-window-inside-pixel-width) (lambda (_window) 700))
               ((symbol-function 'xwidget-window-inside-pixel-height) (lambda (_window) 500))
               ((symbol-function 'xwidget-webkit-stop-loading) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-history) #'ignore)
               ((symbol-function 'xwidget-webkit-callback) #'ignore)
               ((symbol-function '+my/webkit-p) (lambda () t))
               ((symbol-function '+my/mermaid-js-ensure) (lambda () t))
               ((symbol-function '+my/banner-show)
                (lambda (id text &rest args)
                  (push (list id text (plist-get args :actions) (current-buffer)) +test-mermaid--notices))))
       (+test-mermaid--theme +test-mermaid--dark
         (unwind-protect
             (+test-with-reset ,@body)
           (dolist (timer (append timer-list timer-idle-list))
             (let ((function (timer--function timer)))
               (when (and (symbolp function)
                          (string-match-p "\\`\\+my/\\(webkit\\|mermaid-preview\\)" (symbol-name function)))
                 (cancel-timer timer)))))))))

(defun +test-mermaid--timers (function)
  (seq-filter (lambda (timer) (eq (timer--function timer) function))
              (append timer-list timer-idle-list)))

(defun +test-mermaid--fire (function)
  "Run the pending timers calling FUNCTION now, once; how many."
  (let ((timers (+test-mermaid--timers function)))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-mermaid--redisplay ()
  "What redisplay would do: each window showing a WebKit page gets its view."
  (dolist (window (window-list nil 'nomini))
    (when (with-current-buffer (window-buffer window) (derived-mode-p '+my/webkit-mode))
      (+my/webkit--shown-h window)))
  (+test-mermaid--fire #'+my/webkit--start))

(defun +test-mermaid--file (name content)
  "A Mermaid file NAME with CONTENT, visited in the selected window; its buffer."
  (let ((buffer (find-file-noselect (+test-file (concat "mermaid/preview/" name) content))))
    (switch-to-buffer buffer)
    buffer))

(defun +test-mermaid--scripts-matching (regexp)
  (seq-filter (lambda (script) (string-match-p regexp (cadr script))) +test-mermaid--scripts))

(ert-deftest mermaid/preview-opens-beside-the-file ()
  (+test-mermaid--with-webkit
    (let* ((mmd (+test-mermaid--file "flow.mmd" "flowchart TD\n    A --> B\n"))
           (window (selected-window))
           (width (window-total-width window)))
      (call-interactively #'+my/mermaid-preview-toggle)
      (let* ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd))
             (pane (get-buffer-window preview)))
        (should (equal (buffer-name preview) "Diagram: flow.mmd"))
        (should pane)
        ;; Right of the file, half its width; the cursor stays in the file.
        (should (> (window-left-column pane) (window-left-column window)))
        (should (<= (abs (- (window-total-width pane) (/ width 2))) 1))
        (should (eq (selected-window) window))
        (with-current-buffer preview
          (should (eq major-mode '+my/mermaid-preview-page-mode))
          (should (eq +my/mermaid-preview--source mmd)))
        ;; Its page: written as the view starts, the diagram as it is.
        (with-current-buffer mmd (insert "%% typed\n"))
        (+test-mermaid--redisplay)
        (should (= (length +test-mermaid--made) 1))
        (let* ((file (buffer-local-value '+my/mermaid-preview--file mmd))
               (page (+test-mermaid--text file)))
          (should (equal (+test-mermaid--xw-uri (car +test-mermaid--made)) (+my/webkit-file-url file)))
          (should (string-search "show(\"%% typed\\nflowchart TD\\n    A --> B\\n\")" page))
          (should (string-search (+my/mermaid-js-url) page))
          (should (string-search (concat "mmd.init(" (+my/mermaid-theme-json) ")") page)))
        ;; Its colour: the cover's, and around the views.
        (with-current-buffer preview
          (should (equal (+my/webkit--background) "#282c34"))
          (should (member (list :background "#282c34") (alist-get 'default face-remapping-alist))))))))

(ert-deftest mermaid/preview-page ()
  (+test-mermaid--theme +test-mermaid--dark
    (let ((page (+my/mermaid-preview-page "flowchart TD\n    A[\"</script>\"]\n")))
      (should (string-search "<script src=\"file://" page))
      (should (string-search "mermaid-12.3.0/mermaid.min.js\"></script>" page))
      ;; The theme's colours: the page's, its errors'.
      (should (string-search "html{background:#282c34;color:#bbc2cf}" page))
      (should (string-search "#error{color:#ff6c6b;" page))
      ;; A </script> in the diagram doesn't end the page's script.
      (should (= 3 (with-temp-buffer (insert page) (count-matches "</script>" (point-min) (point-max)))))
      (should (string-search "<\\/script>" page))
      (should (string-search "window.mmd" page)))))

(ert-deftest mermaid/preview-follows-typing ()
  "Redrawn ≈0.3 s after typing stops, in each of its views, without reloading."
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "typing.mmd" "flowchart TD\n")))
      (+my/mermaid-preview-show)
      (+test-mermaid--redisplay)
      (setq +test-mermaid--scripts nil)
      (with-current-buffer mmd
        (goto-char (point-max))
        (insert "    A --> B\n"))
      (should (= 1 (length (+test-mermaid--timers #'+my/mermaid-preview--update))))
      (should (< (abs (- 0.3 (float-time (timer--time (car (+test-mermaid--timers #'+my/mermaid-preview--update)))))) 0.001))
      (+test-mermaid--fire #'+my/mermaid-preview--update)
      (should (equal (mapcar #'cadr +test-mermaid--scripts)
                     (list (concat "show(\"flowchart TD\\n    A --> B\\n\");\n;void 0"))))
      (should (= (length +test-mermaid--made) 1)))))

(ert-deftest mermaid/preview-toggled-by-spc-m-p ()
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "toggle.mmd" "flowchart TD\n")))
      (should (eq (+test-mermaid--key "SPC m p") #'+my/mermaid-preview-toggle))
      (with-current-buffer mmd
        (call-interactively #'+my/mermaid-preview-toggle)
        (should +my/mermaid-preview-mode)
        (+test-mermaid--redisplay)
        (let ((file +my/mermaid-preview--file)
              (preview +my/mermaid-preview--buffer))
          (call-interactively #'+my/mermaid-preview-toggle)
          (should-not +my/mermaid-preview-mode)
          (should-not (buffer-live-p preview))
          (should-not (file-exists-p file))
          (should-not (memq #'+my/mermaid-preview--after-change-h after-change-functions))
          (should (= (length (window-list)) 1))
          (should (seq-every-p #'+test-mermaid--xw-killed +test-mermaid--made)))))))

(ert-deftest mermaid/preview-closed-turns-it-off ()
  "Its pane closed (q kills it): the file's preview off; the file killed: the
preview goes."
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "closed.mmd" "flowchart TD\n")))
      (with-current-buffer mmd (+my/mermaid-preview-mode 1))
      (kill-buffer (buffer-local-value '+my/mermaid-preview--buffer mmd))
      (with-current-buffer mmd (should-not +my/mermaid-preview-mode))
      (with-current-buffer mmd (+my/mermaid-preview-mode 1))
      (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
        (kill-buffer mmd)
        (should-not (buffer-live-p preview))))))

(ert-deftest mermaid/preview-shown-again-after-its-pane-closed ()
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "again.mmd" "flowchart TD\n")))
      (+my/mermaid-preview-show)
      (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
        (delete-window (get-buffer-window preview))
        (+my/mermaid-preview-show)
        (should (get-buffer-window preview))
        ;; On screen: nothing more.
        (+my/mermaid-preview-show)
        (should (= (length (get-buffer-window-list preview)) 1))))))

(ert-deftest mermaid/preview-re-themed ()
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "theme.mmd" "flowchart TD\n")))
      (+my/mermaid-preview-show)
      (+test-mermaid--redisplay)
      (setq +test-mermaid--scripts nil)
      (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
        (+test-mermaid--theme +test-mermaid--light
          (run-hooks '+my/mermaid-theme-hook)
          (let ((script (cadr (car (+test-mermaid--scripts-matching "\\`theme(")))))
            (should script)
            (should (string-search (+my/mermaid-theme-json) script))
            (should (string-search "\"#fafafa\", \"#383a42\"" script)))
          (with-current-buffer preview
            (should (member (list :background "#fafafa") (alist-get 'default face-remapping-alist)))))))))

(ert-deftest mermaid/preview-zoom ()
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "zoom.mmd" "flowchart TD\n")))
      (+my/mermaid-preview-show)
      (+test-mermaid--redisplay)
      (with-current-buffer (buffer-local-value '+my/mermaid-preview--buffer mmd)
        (setq +test-mermaid--scripts nil)
        (+my/mermaid-preview-zoom-in)
        (+my/mermaid-preview-zoom-out)
        (+my/mermaid-preview-zoom-reset)
        (should (equal (mapcar (lambda (s) (car (split-string (cadr s) "\n"))) +test-mermaid--scripts)
                       '("zoomBy(1.25);" "zoomBy(0.8);" "zoomBy(0);")))))))

(ert-deftest mermaid/preview-keys ()
  (pcase-dolist (`(,key . ,command)
                 '(("j" . +my/webkit-scroll-down) ("k" . +my/webkit-scroll-up)
                   ("C-d" . +my/webkit-half-screen-down) ("C-u" . +my/webkit-half-screen-up)
                   ("gg" . +my/webkit-top) ("G" . +my/webkit-bottom)
                   ("+" . +my/mermaid-preview-zoom-in) ("=" . +my/mermaid-preview-zoom-in)
                   ("-" . +my/mermaid-preview-zoom-out) ("0" . +my/mermaid-preview-zoom-reset)
                   ("q" . kill-current-buffer)))
    (should (eq (lookup-key (evil-get-auxiliary-keymap +my/mermaid-preview-page-mode-map 'normal) (kbd key))
                command)))
  (should (eq (lookup-key +my/mermaid-preview-page-mode-map [down-mouse-1]) #'+my/webkit-mouse-select))
  (should (eq (lookup-key (evil-get-auxiliary-keymap +my/mermaid-preview-image-mode-map 'normal) "q")
              #'kill-current-buffer)))

;; Without WebKit: mmdc's SVG.

(defmacro +test-mermaid--with-images (&rest body)
  "BODY in a GUI without WebKit (faked), the stand-in mmdc drawing."
  (declare (indent 0))
  `(+test-mermaid--with-mmdc
     (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
               ((symbol-function 'display-graphic-p) (lambda (&rest _) t))
               ((symbol-function 'image-type-available-p) (lambda (&rest _) t)))
       (+test-mermaid--theme +test-mermaid--dark
         (+test-with-reset ,@body)))))

(defun +test-mermaid--image-file (preview)
  "The SVG file PREVIEW's image shows, or nil."
  (with-current-buffer preview
    (let ((pos (text-property-not-all (point-min) (point-max) 'display nil)))
      (and pos (plist-get (cdr (get-text-property pos 'display)) :file)))))

(ert-deftest mermaid/preview-without-webkit-mmdc-s-svg ()
  (+test-mermaid--with-images
    (let ((mmd (+test-mermaid--file "image.mmd" "flowchart TD\n    A --> B\n")))
      (should (+my/mermaid-preview-live-p))
      (+my/mermaid-preview-show)
      (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
        (with-current-buffer preview
          (should (eq major-mode '+my/mermaid-preview-image-mode))
          (should (string-search "Drawing" (buffer-string))))
        (should (+test-mermaid--wait (lambda () (+test-mermaid--image-file preview))))
        (let ((first (+test-mermaid--image-file preview)))
          (should (string-search "flowchart TD" (+test-mermaid--text first)))
          ;; Typed: drawn again once typing pauses (longer: mmdc takes a second).
          (with-current-buffer mmd (goto-char (point-max)) (insert "    B --> C\n"))
          (should (< (abs (- 0.6 (float-time (timer--time (car (+test-mermaid--timers #'+my/mermaid-preview--update)))))) 0.001))
          (+test-mermaid--fire #'+my/mermaid-preview--update)
          (should (+test-mermaid--wait (lambda () (not (equal (+test-mermaid--image-file preview) first)))))
          (should (string-search "B --> C" (+test-mermaid--text (+test-mermaid--image-file preview))))
          ;; An error: Mermaid's message under the last drawing.
          (let ((last (+test-mermaid--image-file preview)))
            (with-current-buffer mmd (insert "    ERROR\n"))
            (+test-mermaid--fire #'+my/mermaid-preview--update)
            (should (+test-mermaid--wait
                     (lambda () (string-search "Parse error" (with-current-buffer preview (buffer-string))))))
            (should (equal (+test-mermaid--image-file preview) last))))))))

(ert-deftest mermaid/preview-in-a-terminal-the-live-editor ()
  (+test-mermaid--with-mmdc
    (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
      (let ((+test-browsed nil))
        (+test-with-reset
          (let ((mmd (+test-mermaid--file "terminal.mmd" "flowchart TD\n")))
            (should-not (+my/mermaid-preview-live-p))
            (with-current-buffer mmd (+my/mermaid-preview-toggle))
            (should-not (buffer-local-value '+my/mermaid-preview-mode mmd))
            (should (string-match-p "mermaid-live-editor" (car +test-browsed)))))))))

;; The notice.

(ert-deftest mermaid/notice-offers-the-preview ()
  (should (eq (default-value '+my/mermaid-preview-notice) t))
  (should (memq #'+my/mermaid-preview-notice-h mermaid-mode-hook))
  (+test-mermaid--with-webkit
    (let ((mmd (+test-mermaid--file "notice.mmd" "flowchart TD\n")))
      (should (equal +test-mermaid--notices
                     (list (list 'mermaid-preview
                                 "See this diagram rendered next to it, updated as you type (SPC m p)."
                                 '(("Open preview" . +my/mermaid-preview-show))
                                 mmd)))))))

(ert-deftest mermaid/notice-only-where-the-preview-works ()
  (+test-mermaid--with-webkit
    (let ((+my/mermaid-preview-notice nil))
      (+test-mermaid--file "off.mmd" "flowchart TD\n"))
    (with-current-buffer (+test-buffer "no file.mmd")
      (mermaid-mode))
    (let ((+my/mermaid-mmdc (expand-file-name "no-such-mmdc" +test-tmp)))
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
        (+test-mermaid--file "terminal-notice.mmd" "flowchart TD\n")))
    (should-not +test-mermaid--notices)))

;; ====== NO COLOUR IN THE CODE ======

(defun +test-mermaid--code-files ()
  (cons (expand-file-name "config/mermaid.el" +test-root)
        (directory-files (expand-file-name "config/mermaid/" +test-root) t "\\.el\\'")))

(defun +test-mermaid--atoms (form)
  "FORM's strings and symbols, nested ones too."
  (cond ((or (stringp form) (symbolp form)) (list form))
        ((consp form) (append (+test-mermaid--atoms (car form)) (+test-mermaid--atoms (cdr form))))
        ((vectorp form) (mapcan #'+test-mermaid--atoms (append form nil)))))

(ert-deftest mermaid/no-colour-in-the-code ()
  "Every colour comes from the theme's faces: no #rrggbb (nor #rgb) in the
code or its comments, no colour name as a string or symbol."
  (dolist (file (+test-mermaid--code-files))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (should-not (re-search-forward "#[0-9a-fA-F]\\{3\\}\\([0-9a-fA-F]\\{3\\}\\)?\\b" nil t))
      (goto-char (point-min))
      (condition-case nil
          (while t
            (dolist (atom (+test-mermaid--atoms (read (current-buffer))))
              (let ((name (if (symbolp atom) (symbol-name atom) atom)))
                (should-not (assoc-string name color-name-rgb-alist t)))))
        (end-of-file)))))
