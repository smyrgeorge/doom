;;; tests/unit/test-mermaid.el -*- lexical-binding: t; -*-
;; config/mermaid.el: Mermaid files in mermaid-mode (highlighted, indented),
;; its commands on SPC m keys, drawing SVGs in Doom's cache in the theme's
;; colours; ```mermaid blocks highlighted in Markdown and agent-shell; Org's
;; mermaid blocks. Mermaid's config from the theme's faces (a stand-in theme:
;; faces' colours faked), its file, a theme switch; no colour in the code.
;; mmdc never runs: `call-process' is faked where a command would run it.

(require 'json)
(+test-load "config/mermaid")
(require 'mermaid-mode)

;; ====== A STAND-IN THEME ======

(defconst +test-mermaid--dark
  '((default :foreground "#bbc2cf" :background "#282c34")
    (shadow :foreground "#5b6268")
    (font-lock-keyword-face :foreground "#51afef")
    (font-lock-function-name-face :foreground "#c678dd")
    (font-lock-string-face :foreground "#98be65")
    (font-lock-type-face :foreground "#ecbe7b")
    (font-lock-builtin-face :foreground "#c678dd")
    (warning :foreground "#ecbe7b")
    (error :foreground "#ff6c6b")
    (success :foreground "#98be65"))
  "doom-one's colours, as faces give them; the other faces have none.")

(defconst +test-mermaid--light
  '((default :foreground "#383a42" :background "#fafafa")
    (font-lock-keyword-face :foreground "#e45649"))
  "A light theme's.")

(defmacro +test-mermaid--theme (faces &rest body)
  "BODY with the faces' colours as FACES says: ((FACE :foreground C
:background C)...), with no colour for any other face (or a default's)."
  (declare (indent 1))
  `(let ((faces ,faces))
     (cl-letf (((symbol-function 'face-foreground)
                (lambda (face &rest _) (plist-get (alist-get face faces) :foreground)))
               ((symbol-function 'face-background)
                (lambda (face &rest _) (plist-get (alist-get face faces) :background))))
       ,@body)))

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

(defmacro +test-mermaid--mmdc (&rest body)
  "BODY with mmdc faked: `runs' the arguments each run was given; the
image it makes not opened (`shown' the buffers that would have been)."
  (declare (indent 0))
  `(let ((runs nil) (shown nil)
         (+my/mermaid--written nil))
     (ignore-errors (delete-file +my/mermaid-config-file))
     (ignore-errors (delete-directory mermaid-tmp-dir t))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program _infile _destination _display &rest args)
                  (should (equal program mermaid-mmdc-location))
                  (push args runs)
                  (with-temp-file (cadr (member "-o" args)) (insert +test-mermaid--svg))
                  0))
               ((symbol-function 'find-file-noselect) (lambda (file &rest _) (get-buffer-create file)))
               ((symbol-function 'display-buffer) (lambda (buffer &rest _) (push buffer shown) nil))
               ((symbol-function 'auto-revert-mode) #'ignore))
       (unwind-protect (progn ,@body)
         (dolist (buffer shown) (kill-buffer buffer))))))

(defconst +test-mermaid--svg
  "<svg id=\"my-svg\" width=\"100%\"><text><tspan>Write</tspan><tspan> the</tspan></text></svg>"
  "An SVG as mmdc writes it: each word of a label in a <tspan>.")

(defun +test-mermaid--arg (args flag)
  (cadr (member flag args)))

(ert-deftest mermaid/draw-the-buffer ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--mmdc
      (with-temp-buffer
        (insert "flowchart TD\n    A --> B\n")
        (mermaid-mode)
        (mermaid-compile-buffer))
      (should (= (length runs) 1))
      (let ((args (car runs)))
        ;; The theme's config written first, given to mmdc.
        (should (equal (+test-mermaid--arg args "-c") +my/mermaid-config-file))
        (should (equal (+test-mermaid--arg args "-b") "transparent"))
        (should (equal (with-temp-buffer (insert-file-contents +my/mermaid-config-file) (buffer-string))
                       (+my/mermaid-config-json)))
        ;; The buffer, and its SVG, in Doom's cache.
        (should (file-in-directory-p (+test-mermaid--arg args "-i") mermaid-tmp-dir))
        (should (equal (with-temp-buffer (insert-file-contents (+test-mermaid--arg args "-i")) (buffer-string))
                       "flowchart TD\n    A --> B\n"))
        (should (string-suffix-p ".svg" (+test-mermaid--arg args "-o")))
        (should (file-in-directory-p (+test-mermaid--arg args "-o") doom-cache-dir)))
      (should (= (length shown) 1)))))

(ert-deftest mermaid/drawn-svg-keeps-its-spaces ()
  "Emacs's SVG library drops a <tspan>'s leading space (\"Writethecode\"):
the SVG's root keeps them, once."
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--mmdc
      (with-temp-buffer
        (insert "flowchart TD\n    A[Write the code]\n")
        (mermaid-mode)
        (mermaid-compile-buffer)
        (let ((svg (+test-mermaid--arg (car runs) "-o")))
          (should (string-prefix-p "<svg xml:space=\"preserve\" id=\"my-svg\""
                                   (with-temp-buffer (insert-file-contents svg) (buffer-string))))
          (+my/mermaid-fix-svg svg)
          (should (= 1 (with-temp-buffer (insert-file-contents svg) (count-matches "xml:space" (point-min) (point-max))))))))))

(ert-deftest mermaid/draw-the-region ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--mmdc
      (with-temp-buffer
        (insert "%% not this\nflowchart TD\n    A --> B\n")
        (mermaid-mode)
        (transient-mark-mode 1)
        (goto-char (point-min))
        (forward-line 1)
        (push-mark (point) t t)
        (goto-char (point-max))
        (mermaid-compile-region))
      (should (= (length runs) 1))
      (should (equal (with-temp-buffer (insert-file-contents (+test-mermaid--arg (car runs) "-i")) (buffer-string))
                     "flowchart TD\n    A --> B\n")))))

(ert-deftest mermaid/draw-the-file-next-to-it ()
  (+test-mermaid--theme +test-mermaid--dark
    (+test-mermaid--mmdc
      (let ((file (+test-file "mermaid/next/flow.mmd" "flowchart TD\n    A --> B\n")))
        (with-temp-buffer
          (insert-file-contents file)
          (setq buffer-file-name file)
          (mermaid-mode)
          (mermaid-compile)
          (set-buffer-modified-p nil))
        (let ((args (car runs)))
          (should (equal (+test-mermaid--arg args "-i") file))
          (should (equal (+test-mermaid--arg args "-o") (concat (file-name-sans-extension file) ".svg")))
          (should (equal (+test-mermaid--arg args "-c") +my/mermaid-config-file)))))))

(ert-deftest mermaid/a-theme-switch-reaches-the-commands ()
  "A command run after a theme switch draws in the new theme's colours."
  (+test-mermaid--mmdc
    (with-temp-buffer
      (insert "flowchart TD\n    A --> B\n")
      (mermaid-mode)
      (+test-mermaid--theme +test-mermaid--dark (mermaid-compile-buffer))
      (+test-mermaid--theme +test-mermaid--light
        (mermaid-compile-buffer)
        (should (equal (with-temp-buffer (insert-file-contents +my/mermaid-config-file) (buffer-string))
                       (+my/mermaid-config-json)))
        (should (string-match-p "\"darkMode\":false" (+my/mermaid-config-json)))))))

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
                 (with-temp-file svg (insert +test-mermaid--svg))
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
        (when (and (stringp (cdr pair)) (string-match-p "Color\\|Bkg\\|background\\|\\`pie[0-9]\\|\\`git\\|\\`cScale" (symbol-name (car pair))))
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
      (+test-mermaid--theme +test-mermaid--dark
        (+my/mermaid-write-config)
        (+my/mermaid-theme-h))
      (should (= ran 1))
      (+test-mermaid--theme +test-mermaid--light
        (+my/mermaid-theme-h)
        (should (= ran 2))
        (should (equal (+test-mermaid--file-text) (+my/mermaid-config-json)))
        ;; The same theme loaded again: nothing changed, nothing run.
        (+my/mermaid-theme-h)
        (should (= ran 2))))))

(ert-deftest mermaid/theme-switch-writes-nothing-before-mermaid-is-used ()
  (let ((+my/mermaid--written nil)
        (+my/mermaid--json nil)
        (+my/mermaid-theme-hook nil))
    (ignore-errors (delete-file +my/mermaid-config-file))
    (+test-mermaid--theme +test-mermaid--dark (+my/mermaid-theme-h))
    (should-not (file-exists-p +my/mermaid-config-file))))

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
