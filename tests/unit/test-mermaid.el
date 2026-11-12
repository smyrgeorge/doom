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
  `(let ((faces ,faces)
         (+my/mermaid--json nil))
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

;; ====== A STAND-IN MMDC ======
;; A script taking mmdc's arguments: the source on its input, its SVG (the
;; source and the config it was given in it) written to -o; a source saying
;; ERROR fails as Mermaid does, SLOW takes 3 s. Each run's arguments logged.

(defconst +test-mermaid--mmdc-script
  "#!/bin/sh
dir=$(dirname \"$0\")
echo \"$*\" >> \"$dir/runs.log\"
out= config=
while [ $# -gt 0 ]; do
  case \"$1\" in -o) out=$2; shift ;; -c) config=$2; shift ;; esac
  shift
done
source=$(cat)
case \"$source\" in *SLOW*) sleep 3 ;; esac
case \"$source\" in
  *ERROR*)
    echo 'Error: Parse error on line 2:' >&2
    echo '...A --> ERROR' >&2
    echo \"Expecting 'SEMI', got 'NODE_STRING'\" >&2
    echo 'Parser.parseError (https://mermaid-cli-intercept.invalid/mermaid.mjs:1:2)' >&2
    echo '    at async renderMermaid (file:///mmdc/src/index.js:690:22)' >&2
    exit 1 ;;
esac
{ printf '<svg id=\"my-svg\"><text><tspan>Write</tspan><tspan> the</tspan></text>'
  printf '<desc>%s</desc><desc>' \"$source\"; cat \"$config\"; printf '</desc></svg>'; } > \"$out\"
"
  "The stand-in mmdc (see above).")

(defun +test-mermaid--make-mmdc ()
  "A stand-in mmdc in a folder of its own: its path."
  (let ((file (expand-file-name "mmdc" (make-temp-file (+test-tmp-file "mermaid/bin-") t))))
    (with-temp-file file (insert +test-mermaid--mmdc-script))
    (set-file-modes file #o755)
    file))

(defmacro +test-mermaid--with-mmdc (&rest body)
  "BODY with the stand-in mmdc, an empty cache, no drawing waiting: `mmdc' its
path; `shown' the buffers the commands would show."
  (declare (indent 0))
  `(let* ((mmdc (+test-mermaid--make-mmdc))
          (+my/mermaid-mmdc mmdc)
          (mermaid-mmdc-location mmdc)
          (+my/mermaid-cache-directory (file-name-as-directory (make-temp-file (+test-tmp-file "mermaid/cache-") t)))
          (+my/mermaid--waiting (make-hash-table :test #'equal))
          (+my/mermaid--queue nil)
          (+my/mermaid--running 0)
          (+my/mermaid--pruned t)
          (+my/mermaid--written nil)
          (shown nil))
     (cl-letf (((symbol-function 'display-buffer) (lambda (buffer &rest _) (push buffer shown) nil)))
       (unwind-protect (progn ,@body)
         (dolist (process (process-list))
           (when (equal (process-name process) "mmdc") (delete-process process)))
         (dolist (buffer shown)
           (when (buffer-live-p (get-buffer buffer))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))))))

(defun +test-mermaid--runs (mmdc)
  "The stand-in MMDC's runs: each its arguments (a list), oldest first."
  (let ((log (expand-file-name "runs.log" (file-name-directory mmdc))))
    (when (file-exists-p log)
      (mapcar #'split-string
              (split-string (with-temp-buffer (insert-file-contents log) (buffer-string)) "\n" t)))))

(defun +test-mermaid--wait (predicate &optional seconds)
  "Wait (processes and timers running) until PREDICATE, SECONDS at most (10)."
  (let ((end (+ (float-time) (or seconds 10))))
    (while (and (not (funcall predicate)) (< (float-time) end))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun +test-mermaid--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun +test-mermaid--arg (args flag)
  (cadr (member flag args)))

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
