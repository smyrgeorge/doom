;;; $DOOMDIR/config/agent-ui/elements/math.el -*- lexical-binding: t; -*-
;; Agent UI's math: formulas typeset (LaTeX math), for explanations of
;; algorithms, statistics, physics. Loaded from config/agent-ui/elements.el.
;;
;; In the GUI, an image typeset in the background by a tool, if one is
;; installed (`agent-ui-math-tool'): MathJax through node (npm install -g
;; mathjax-full; elements/math/tex2svg.js), or LaTeX and dvisvgm. Cached
;; by the formula's hash (`agent-ui-math-cache-directory'), sized to the font,
;; in the theme's text colour; until it's there, its text. In a terminal, or
;; without a tool: a Unicode rendering where it's simple (α ≤ ∑ᵢ xᵢ²), else
;; the source, and in the GUI a line saying what to install. Nothing waits
;; for the tool: Emacs goes on.
;;
;;   E = mc²
;;   ∑ᵢ₌₁ⁿ i = (n(n+1))/(2)

(require 'cl-lib)
(require 'subr-x)

(defvar agent-ui-math-tool 'auto
  "What typesets formulas: mathjax, latex, none, or auto (the first there:
MathJax's package in node's global modules, else latex and dvisvgm).")

(defvar agent-ui-math-cache-directory (locate-user-emacs-file "agent-ui/math/")
  "Where typeset formulas are kept, by their hash.")

(defconst agent-ui-math--script
  (expand-file-name "math/tex2svg.js" (file-name-directory (or load-file-name buffer-file-name)))
  "The MathJax script node runs.")

(defvar agent-ui-math--results (make-hash-table :test #'equal)
  "Formulas typeset or failing, by key: (:file FILE) or (:error TEXT).")

(defvar agent-ui-math--running nil
  "The keys of the formulas being typeset.")

;; ====== THE TOOL ======

(defun agent-ui-math--node-modules ()
  "Node's global modules, beside its binary (Homebrew's /opt/homebrew/lib,
nvm's), or nil."
  (when-let* ((node (executable-find "node")))
    (seq-find #'file-directory-p
              (mapcar (lambda (bin) (expand-file-name "../lib/node_modules/" (file-name-directory bin)))
                      (list node (file-truename node))))))

(defun agent-ui-math--tool ()
  "The tool typesetting formulas here: mathjax, latex, or nil."
  (pcase agent-ui-math-tool
    ('none nil)
    ('auto (cond ((when-let* ((modules (agent-ui-math--node-modules)))
                    (file-directory-p (expand-file-name "mathjax-full" modules)))
                  'mathjax)
                 ((and (executable-find "latex") (executable-find "dvisvgm")) 'latex)))
    (tool tool)))

(defun agent-ui-math--color ()
  "The theme's text colour, #RRGGBB."
  (let ((rgb (color-name-to-rgb (agent-ui-color 'default))))
    (if rgb (apply #'color-rgb-to-hex (append rgb '(2))) "#888888")))

(defun agent-ui-math--key (tool tex display color)
  (secure-hash 'sha1 (format "%s|%s|%s|%s" tool display color tex)))

(defun agent-ui-math--command (tool display dir)
  "TOOL's command typesetting the formula (on its stdin for MathJax; in DIR's
m.tex for LaTeX), its SVG on stdout."
  (pcase tool
    ('mathjax (list "node" agent-ui-math--script (if (eq display 'inline) "inline" "block")))
    ('latex (list "sh" "-c"
                  (format "cd %s && latex -interaction=nonstopmode -halt-on-error m.tex >m.out 2>&1 || { grep '^!' m.out >&2; exit 1; }; dvisvgm --no-fonts --exact-bbox --stdout m.dvi 2>/dev/null"
                          (shell-quote-argument dir))))))

(defun agent-ui-math--latex-source (tex display color)
  "A LaTeX document with TEX alone on its page, in COLOR."
  (format "\\documentclass[10pt]{article}\n\\usepackage{amsmath,amssymb,xcolor}\n\\pagestyle{empty}\n\\definecolor{fg}{HTML}{%s}\n\\begin{document}\n\\color{fg}%s\n\\end{document}\n"
          (upcase (substring color 1))
          (if (eq display 'inline) (concat "$" tex "$") (concat "\\[" tex "\\]"))))

(defun agent-ui-math--typeset (tool tex display color key)
  "Typeset TEX in the background with TOOL; then its elements redrawn."
  (unless (member key agent-ui-math--running)
    (push key agent-ui-math--running)
    (let* ((dir (make-temp-file "agent-ui-math-" t))
           (out (generate-new-buffer " *agent-ui math*"))
           (err (generate-new-buffer " *agent-ui math errors*"))
           (process nil)
           ;; Done once the tool has exited and its errors are all read: its
           ;; sentinel could run before the last of them came (its error read
           ;; "it failed").
           (waiting 2)
           (done
            (lambda ()
              (when (zerop (cl-decf waiting))
                (setq agent-ui-math--running (delete key agent-ui-math--running))
                (let ((svg (with-current-buffer out (buffer-string)))
                      (message (string-trim (with-current-buffer err (buffer-string)))))
                  (puthash key
                           (if (and (zerop (process-exit-status process)) (string-match-p "<svg" svg))
                               (let ((file (expand-file-name (concat key ".svg") agent-ui-math-cache-directory)))
                                 (make-directory agent-ui-math-cache-directory t)
                                 (with-temp-file file
                                   ;; MathJax's glyphs take the text's colour.
                                   (insert (string-replace "currentColor" color svg)))
                                 (list :file file))
                             (list :error (car (split-string (if (string-empty-p message) "it failed" message)
                                                             "\n"))))
                           agent-ui-math--results))
                (kill-buffer out)
                (kill-buffer err)
                (delete-directory dir t)
                (agent-ui-math--redraw key))))
           (stderr (make-pipe-process
                    :name "agent-ui-math errors" :buffer err :noquery t
                    :sentinel (lambda (pipe _event)
                                (unless (process-live-p pipe) (funcall done))))))
      (when (eq tool 'latex)
        (with-temp-file (expand-file-name "m.tex" dir)
          (insert (agent-ui-math--latex-source tex display color))))
      (let ((process-environment
             ;; Node finds the global MathJax through NODE_PATH only.
             (if-let* ((modules (and (eq tool 'mathjax) (agent-ui-math--node-modules))))
                 (cons (concat "NODE_PATH=" (directory-file-name modules)) process-environment)
               process-environment)))
        (condition-case failed
            (setq process
                  (make-process
                   :name "agent-ui-math" :buffer out :stderr stderr :noquery t :connection-type 'pipe
                   :command (agent-ui-math--command tool display dir)
                   :sentinel (lambda (process _event)
                               (when (memq (process-status process) '(exit signal))
                                 (funcall done)))))
          (error (delete-process stderr)
                 (kill-buffer out)
                 (kill-buffer err)
                 (delete-directory dir t)
                 (setq agent-ui-math--running (delete key agent-ui-math--running))
                 (signal (car failed) (cdr failed)))))
      (when (eq tool 'mathjax)
        (process-send-string process tex)
        (process-send-eof process)))))

(defun agent-ui-math--redraw (key)
  "Redraw the math elements showing KEY's formula, everywhere."
  (cl-flet ((mine-p (element)
              (and (equal (plist-get element :type) "math")
                   (equal key (agent-ui-math--key (agent-ui-math--tool) (plist-get element :tex)
                                                  (agent-ui-math--display element) (agent-ui-math--color))))))
    (dolist (canvas (agent-ui-canvases))
      (with-current-buffer canvas
        (agent-ui--dirty
         (cl-loop for id in agent-ui--order
                  for element = (agent-ui--entry-element (gethash id agent-ui--entries))
                  when (or (mine-p element) (seq-some #'mine-p (agent-ui--descendants element)))
                  collect id))))))

(defun agent-ui-math--display (props)
  (if (member (format "%s" (plist-get props :display)) '("inline")) 'inline 'block))

;; ====== AS UNICODE ======

(defconst agent-ui-math--symbols
  '(("alpha" . "α") ("beta" . "β") ("gamma" . "γ") ("delta" . "δ") ("epsilon" . "ε") ("varepsilon" . "ε")
    ("zeta" . "ζ") ("eta" . "η") ("theta" . "θ") ("iota" . "ι") ("kappa" . "κ") ("lambda" . "λ") ("mu" . "μ")
    ("nu" . "ν") ("xi" . "ξ") ("pi" . "π") ("rho" . "ρ") ("sigma" . "σ") ("tau" . "τ") ("upsilon" . "υ")
    ("phi" . "φ") ("varphi" . "φ") ("chi" . "χ") ("psi" . "ψ") ("omega" . "ω")
    ("Gamma" . "Γ") ("Delta" . "Δ") ("Theta" . "Θ") ("Lambda" . "Λ") ("Xi" . "Ξ") ("Pi" . "Π") ("Sigma" . "Σ")
    ("Phi" . "Φ") ("Psi" . "Ψ") ("Omega" . "Ω")
    ("sum" . "∑") ("prod" . "∏") ("int" . "∫") ("oint" . "∮") ("infty" . "∞") ("partial" . "∂") ("nabla" . "∇")
    ("cdot" . "·") ("times" . "×") ("div" . "÷") ("pm" . "±") ("mp" . "∓") ("le" . "≤") ("leq" . "≤")
    ("ge" . "≥") ("geq" . "≥") ("ne" . "≠") ("neq" . "≠") ("approx" . "≈") ("equiv" . "≡") ("sim" . "∼")
    ("propto" . "∝") ("to" . "→") ("rightarrow" . "→") ("leftarrow" . "←") ("Rightarrow" . "⇒")
    ("Leftrightarrow" . "⇔") ("iff" . "⇔") ("implies" . "⇒") ("mapsto" . "↦") ("in" . "∈") ("notin" . "∉")
    ("subset" . "⊂") ("subseteq" . "⊆") ("cup" . "∪") ("cap" . "∩") ("emptyset" . "∅") ("forall" . "∀")
    ("exists" . "∃") ("neg" . "¬") ("land" . "∧") ("lor" . "∨") ("ldots" . "…") ("cdots" . "⋯") ("dots" . "…")
    ("quad" . "  ") ("qquad" . "    ") ("," . " ") (";" . " ") ("!" . "") ("log" . "log") ("ln" . "ln")
    ("sin" . "sin") ("cos" . "cos") ("tan" . "tan") ("exp" . "exp") ("max" . "max") ("min" . "min")
    ("lim" . "lim") ("left" . "") ("right" . "") ("{" . "{") ("}" . "}") ("mid" . "|")
    ("langle" . "⟨") ("rangle" . "⟩") ("ell" . "ℓ") ("hbar" . "ℏ") ("circ" . "∘") ("star" . "⋆")
    ("leftrightarrow" . "↔") ("uparrow" . "↑") ("downarrow" . "↓") ("perp" . "⊥") ("angle" . "∠"))
  "TeX's commands with a Unicode character (or word) of their own.")

(defconst agent-ui-math--supers
  '((?0 . ?⁰) (?1 . ?¹) (?2 . ?²) (?3 . ?³) (?4 . ?⁴) (?5 . ?⁵) (?6 . ?⁶) (?7 . ?⁷) (?8 . ?⁸) (?9 . ?⁹)
    (?+ . ?⁺) (?- . ?⁻) (?= . ?⁼) (?\( . ?⁽) (?\) . ?⁾) (?n . ?ⁿ) (?i . ?ⁱ) (?T . ?ᵀ) (?k . ?ᵏ) (?x . ?ˣ)))

(defconst agent-ui-math--subs
  '((?0 . ?₀) (?1 . ?₁) (?2 . ?₂) (?3 . ?₃) (?4 . ?₄) (?5 . ?₅) (?6 . ?₆) (?7 . ?₇) (?8 . ?₈) (?9 . ?₉)
    (?+ . ?₊) (?- . ?₋) (?= . ?₌) (?\( . ?₍) (?\) . ?₎) (?a . ?ₐ) (?e . ?ₑ) (?o . ?ₒ) (?x . ?ₓ) (?h . ?ₕ)
    (?k . ?ₖ) (?l . ?ₗ) (?m . ?ₘ) (?n . ?ₙ) (?p . ?ₚ) (?s . ?ₛ) (?t . ?ₜ) (?i . ?ᵢ) (?j . ?ⱼ) (?r . ?ᵣ)
    (?u . ?ᵤ) (?v . ?ᵥ)))

(defun agent-ui-math--script-of (text table)
  "TEXT in TABLE's script (superscripts, subscripts), or nil if a character
has none."
  (let ((chars (mapcar (lambda (c) (cdr (assq c table))) (string-to-list text))))
    (and (not (memq nil chars)) (apply #'string chars))))

(defun agent-ui-math-unicode (tex)
  "TEX (math) in Unicode where it's simple: α ≤ ∑ᵢ xᵢ², (a)/(b), √(x); nil
if a command or a script has none."
  (catch 'hard
    (let ((s tex)
          (group "{\\([^{}]*\\)}"))
      ;; Innermost first, again while something changes.
      (let ((before nil))
        (while (not (equal s before))
          (setq before s)
          (setq s (replace-regexp-in-string
                   (concat "\\\\\\(?:text\\|mathrm\\|mathit\\|operatorname\\|mathbf\\)" group) "\\1" s t))
          (setq s (replace-regexp-in-string
                   (concat "\\\\mathbb" group)
                   (lambda (m) (let ((c (match-string 1 m)))
                                 (or (cdr (assoc c '(("R" . "ℝ") ("N" . "ℕ") ("Z" . "ℤ") ("Q" . "ℚ") ("C" . "ℂ"))))
                                     (throw 'hard nil))))
                   s t t))
          (setq s (replace-regexp-in-string
                   (concat "\\\\frac" group group)
                   (lambda (m) (let ((a (match-string 1 m)) (b (match-string 2 m)))
                                 (concat (if (> (length a) 1) (concat "(" a ")") a) "/"
                                         (if (> (length b) 1) (concat "(" b ")") b))))
                   s t t))
          (setq s (replace-regexp-in-string
                   (concat "\\\\sqrt" group)
                   (lambda (m) (let ((a (match-string 1 m))) (if (> (length a) 1) (concat "√(" a ")") (concat "√" a))))
                   s t t))
          (dolist (pair (list (cons "\\^" agent-ui-math--supers) (cons "_" agent-ui-math--subs)))
            (setq s (replace-regexp-in-string
                     (concat (car pair) "\\(?:" group "\\|\\([^{}\\\\ ]\\)\\)")
                     (lambda (m) (or (agent-ui-math--script-of (or (match-string 1 m) (match-string 2 m)) (cdr pair))
                                     (throw 'hard nil)))
                     s t t)))))
      ;; Its commands.
      (setq s (replace-regexp-in-string
               "\\\\\\([A-Za-z]+\\|[,;!{}]\\)"
               (lambda (m) (or (cdr (assoc (match-string 1 m) agent-ui-math--symbols)) (throw 'hard nil)))
               s t t))
      (when (string-match-p "[\\\\^_]" s) (throw 'hard nil))
      (string-trim (replace-regexp-in-string "[{}]" "" s)))))

;; ====== DRAWING ======

(defun agent-ui-math--image (file display ctx)
  "FILE's SVG as an image sized to CTX's font (MathJax's ex, LaTeX's pt as
pixels), no wider than its width."
  (let* ((lh (plist-get ctx :line-height))
         (svg (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (px (lambda (n unit) (* n (pcase unit ("ex" (* 0.36 lh)) ("pt" (* 0.08 lh)) (_ 1.0)))))
         (width nil))
    (setq svg (replace-regexp-in-string
               "\\(\\(?:width\\|height\\)=[\"']\\)\\([0-9.]+\\)\\(ex\\|pt\\)\\([\"']\\)"
               (lambda (m)
                 (let ((value (funcall px (string-to-number (match-string 2 m)) (match-string 3 m))))
                   (when (and (null width) (string-prefix-p "width" (match-string 1 m)))
                     (setq width value))
                   (format "%s%.2f%s" (match-string 1 m) value (match-string 4 m))))
               svg t t))
    (let ((room (* (plist-get ctx :char-width) (- (plist-get ctx :width) (if (eq display 'block) 2 0)))))
      (propertize "math" 'display
                  (agent-ui-image
                   (create-image svg 'svg t :ascent 'center
                                 :scale (if (and width (> width room)) (/ room width) 1)))))))

(defun agent-ui-math--wrap (text width indent)
  "TEXT (a formula's source, or its Unicode) in lines WIDTH wide, each led
by INDENT: broken at its spaces and before its commands (\\alpha), not
within one (it broke \\delt / a, its next lines not indented)."
  (let ((room (max 1 (- width (string-width indent))))
        (atoms nil) (start 0) (lines nil) (line ""))
    ;; Its pieces: each up to a space's end or a command's start.
    (dotimes (i (length text))
      (when (and (> i start)
                 (or (eq (aref text (1- i)) ?\s)
                     (and (eq (aref text i) ?\\) (not (eq (aref text (1- i)) ?\\)))))
        (push (substring text start i) atoms)
        (setq start i)))
    (push (substring text start) atoms)
    (dolist (atom (nreverse atoms))
      (if (and (not (string-empty-p line))
               (> (+ (string-width line) (string-width (string-trim-right atom))) room))
          (progn (push (string-trim-right line) lines)
                 (setq line (string-trim-left atom)))
        (setq line (concat line atom))))
    (push (string-trim-right line) lines)
    ;; A piece wider than the room: cut within it.
    (mapconcat (lambda (l) (concat indent (replace-regexp-in-string "\n" (concat "\n" indent) (agent-ui-wrap l room) t t)))
               (nreverse lines) "\n")))

(defun agent-ui-math--draw (props ctx)
  (let* ((tex (string-trim (plist-get props :tex)))
         (display (agent-ui-math--display props))
         (indent (if (eq display 'block) "  " ""))
         (width (plist-get ctx :width))
         (unicode (agent-ui-math-unicode tex))
         (as-text (agent-ui-math--wrap (or unicode tex) width indent))
         (gui (and (plist-get ctx :graphic) (plist-get ctx :line-height) (plist-get ctx :char-width)))
         (tool (and gui (agent-ui-math--tool))))
    (cond
     ((not gui) as-text)
     ;; No tool: its Unicode; its source, with what would typeset it.
     ((null tool)
      (if unicode
          as-text
        (concat as-text "\n"
                (propertize (agent-ui-wrap "Formulas are typeset with MathJax (npm install -g mathjax-full) or LaTeX and dvisvgm."
                                           width)
                            'face 'agent-ui-muted))))
     (t
      (let* ((color (agent-ui-math--color))
             (key (agent-ui-math--key tool tex display color))
             (result (gethash key agent-ui-math--results))
             (cached (expand-file-name (concat key ".svg") agent-ui-math-cache-directory)))
        (when (and (null result) (file-readable-p cached))
          (setq result (puthash key (list :file cached) agent-ui-math--results)))
        (cond
         ((plist-get result :file)
          (concat indent (agent-ui-math--image (plist-get result :file) display ctx)))
         ((plist-get result :error)
          (concat as-text "\n" (propertize (agent-ui-wrap (concat "Not typeset: " (plist-get result :error)) width)
                                           'face 'agent-ui-error)))
         (t
          ;; Typeset in the background; its text meanwhile.
          (agent-ui-math--typeset tool tex display color key)
          (concat as-text "\n" (propertize "typesetting…" 'face 'agent-ui-muted)))))))))

(agent-ui-define math
  "Formulas typeset (LaTeX math): TEX, without $ or \\[; DISPLAY block (on
its own, larger; the default) or inline. An image in the GUI (MathJax or
LaTeX, if installed), Unicode where simple or the source in a terminal."
  :props ((tex string "The formula, LaTeX math: \\\\frac{a}{b}, \\\\sum_{i=1}^n" :required t)
          (display (choice block inline) "On its own, larger (block), or as in a sentence" :default block))
  :example (:title "Gauss" :tex "\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}")
  :text #'agent-ui-math--draw)
