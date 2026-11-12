;;; $DOOMDIR/config/mermaid/theme.el -*- lexical-binding: t; -*-
;; Mermaid's config in the theme's colours. Loaded from config/mermaid.el.

(require 'color)

;; THE THEME'S COLOURS (see config/mermaid.el)
;; Each colour Mermaid's base theme takes, from a face: (VARIABLE FACE
;; ATTRIBUTE [AMOUNT]), AMOUNT blending the colour into the theme's background
;; (a tint of it: a node's fill). The others Mermaid works out from these.
(defconst +my/mermaid--colours
  '((background            default                      :background)
    (primaryColor          font-lock-keyword-face       :foreground 0.18)
    (primaryTextColor      default                      :foreground)
    (primaryBorderColor    font-lock-keyword-face       :foreground)
    (secondaryColor        font-lock-function-name-face :foreground 0.18)
    (secondaryTextColor    default                      :foreground)
    (secondaryBorderColor  font-lock-function-name-face :foreground)
    (tertiaryColor         default                      :foreground 0.06)
    (tertiaryTextColor     default                      :foreground)
    (tertiaryBorderColor   shadow                       :foreground)
    (lineColor             default                      :foreground 0.6)
    (actorLineColor        shadow                       :foreground)
    (textColor             default                      :foreground)
    (titleColor            default                      :foreground)
    (edgeLabelBackground   default                      :background)
    (noteBkgColor          warning                      :foreground 0.18)
    (noteTextColor         default                      :foreground)
    (noteBorderColor       warning                      :foreground)
    (errorBkgColor         error                        :foreground 0.18)
    (errorTextColor        error                        :foreground)
    (critBkgColor          error                        :foreground 0.35)
    (critBorderColor       error                        :foreground)
    (todayLineColor        error                        :foreground)
    (doneTaskBkgColor      shadow                       :foreground 0.5)
    (doneTaskBorderColor   shadow                       :foreground)
    (altSectionBkgColor    default                      :background)
    (gridColor             shadow                       :foreground)
    (pieTitleTextColor     default                      :foreground)
    (pieLegendTextColor    default                      :foreground)
    (pieSectionTextColor   default                      :background)
    (pieStrokeColor        default                      :background)
    (pieOuterStrokeColor   default                      :background))
  "Mermaid's colours from faces: (VARIABLE FACE ATTRIBUTE [AMOUNT]), see above.")

;; Series (a pie's slices, a git graph's branches, a mindmap's levels, an xy
;; chart's lines): the theme's accents, each colour once, in this order.
(defconst +my/mermaid--accents
  '(font-lock-keyword-face font-lock-string-face font-lock-type-face
    font-lock-function-name-face error font-lock-constant-face
    font-lock-variable-name-face font-lock-builtin-face success warning link
    font-lock-doc-face)
  "Faces whose foregrounds colour a diagram's series.")

(defun +my/mermaid--frame ()
  "The frame whose faces give the colours: a graphical one if there's one (the
theme's true colours: the GUI's server makes terminal frames too), else the
selected frame."
  (or (seq-find #'display-graphic-p (frame-list)) (selected-frame)))

(defun +my/mermaid--rgb (colour &optional frame)
  "COLOUR (#rrggbb or a name) as (R G B), each 0 to 1; nil if unspecified. A
name by X's table first: a terminal frame would give its palette's nearest."
  (when (and (stringp colour) (not (string-prefix-p "unspecified" colour)))
    (if-let* ((values (or (color-values-from-color-spec colour)
                          (cdr (assoc-string colour color-name-rgb-alist t)))))
        (mapcar (lambda (value) (/ value 65535.0)) values)
      (color-name-to-rgb colour frame))))

(defun +my/mermaid--hex (colour frame)
  "COLOUR (#rrggbb or a name) as #rrggbb, nil if unspecified."
  (when-let* ((rgb (+my/mermaid--rgb colour frame)))
    (apply #'color-rgb-to-hex (append rgb '(2)))))

(defun +my/mermaid--face-colour (face attribute frame)
  "FACE's ATTRIBUTE (:foreground or :background) on FRAME as #rrggbb, inherited,
else default's; nil if default has none either (a batch Emacs)."
  (let ((get (if (eq attribute :background) #'face-background #'face-foreground)))
    (or (+my/mermaid--hex (funcall get face frame t) frame)
        (+my/mermaid--hex (funcall get 'default frame) frame))))

(defun +my/mermaid--blend (colour background amount)
  "COLOUR blended into BACKGROUND (both #rrggbb), AMOUNT of it."
  (apply #'color-rgb-to-hex
         (append (color-blend (+my/mermaid--rgb colour) (+my/mermaid--rgb background) amount)
                 '(2))))

(defun +my/mermaid--accent-colours (frame)
  "The accents' colours on FRAME (see `+my/mermaid--accents'), each once."
  (delete-dups (delq nil (mapcar (lambda (face)
                                   (when (facep face)
                                     (+my/mermaid--hex (face-foreground face frame t) frame)))
                                 +my/mermaid--accents))))

(defun +my/mermaid--series (prefix count colours &optional start)
  "PREFIX0.. (from START) .. COUNT variables, COLOURS in turn: ((pie1 . C)...)."
  (when colours
    (cl-loop for i below count
             collect (cons (intern (format "%s%d" prefix (+ i (or start 0))))
                           (nth (mod i (length colours)) colours)))))

(defun +my/mermaid--font (frame)
  "((fontFamily . F) (fontSize . S)): the default face's font on FRAME, where
it has one (a graphical frame)."
  (let ((family (face-attribute 'default :family frame t))
        (font (and (display-graphic-p frame) (face-font 'default frame))))
    (append (when (and (stringp family) (not (member family '("default" "unspecified"))))
              (list (cons 'fontFamily (format "\"%s\", monospace" family))))
            (when-let* ((info (and font (font-info font frame)))
                        (size (aref info 2))
                        ((> size 0)))
              (list (cons 'fontSize (format "%dpx" size)))))))

(defun +my/mermaid--css (background)
  "CSS for what Mermaid colours without its theme: an ER diagram's zero
\(a circle, white) hollow, the BACKGROUND's colour."
  (when background
    (format "[id*=\"_er-\"] circle { fill: %s; }" background)))

(defun +my/mermaid-config ()
  "Mermaid's config in the current theme's colours: an alist for
`json-serialize' (mmdc's -c file, mermaid.initialize in a page). Its base
theme, every colour from a face (see `+my/mermaid--colours'): none written
here. The classic look: the newer one's borders blend two colours and its
shadows glow on a dark background. HTML labels off: SVG's own text, which
Emacs's SVG library draws (it draws no HTML)."
  (let* ((frame (+my/mermaid--frame))
         (background (+my/mermaid--face-colour 'default :background frame))
         (accents (+my/mermaid--accent-colours frame))
         (tints (and background
                     (mapcar (lambda (colour) (+my/mermaid--blend colour background 0.35)) accents)))
         (foreground (+my/mermaid--face-colour 'default :foreground frame))
         (variables
          (append
           (list (cons 'darkMode (if (if background
                                         (color-dark-p (+my/mermaid--rgb background))
                                       (eq (frame-parameter frame 'background-mode) 'dark))
                                     t :false)))
           (+my/mermaid--font frame)
           (cl-loop for (variable face attribute amount) in +my/mermaid--colours
                    for colour = (+my/mermaid--face-colour face attribute frame)
                    when (and colour (or (not amount) background))
                    collect (cons variable (if amount (+my/mermaid--blend colour background amount) colour)))
           (+my/mermaid--series "pie" 12 accents 1)
           (+my/mermaid--series "git" 8 accents)
           (and background (+my/mermaid--series "gitBranchLabel" 8 (list background)))
           (+my/mermaid--series "cScale" 12 tints)
           (and foreground (+my/mermaid--series "cScaleLabel" 12 (list foreground)))
           (when accents
             (list (cons 'xyChart (list (cons 'plotColorPalette (string-join accents ", ")))))))))
    `((theme . "base")
      (look . "classic")
      (themeVariables . ,variables)
      ,@(when-let* ((css (+my/mermaid--css background)))
          (list (cons 'themeCSS css)))
      (htmlLabels . :false)
      (flowchart (htmlLabels . :false)))))

(defun +my/mermaid-config-json ()
  "`+my/mermaid-config' as JSON."
  (decode-coding-string (json-serialize (+my/mermaid-config)) 'utf-8))

;; THE CONFIG'S FILE (mmdc -c)
(defvar +my/mermaid--written nil
  "The JSON last written to `+my/mermaid-config-file' (this session).")

(defun +my/mermaid-write-config ()
  "Write the theme's config to `+my/mermaid-config-file', unless it's there as
it is; return the file."
  (let ((json (+my/mermaid-config-json)))
    (unless (and (equal json +my/mermaid--written) (file-exists-p +my/mermaid-config-file))
      (make-directory (file-name-directory +my/mermaid-config-file) t)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region json nil +my/mermaid-config-file nil 'silent))
      (setq +my/mermaid--written json))
    +my/mermaid-config-file))

;; A THEME SWITCH
(defvar +my/mermaid-theme-hook nil
  "Run when a theme switch changed Mermaid's config (its file rewritten):
previews re-themed, diagrams drawn again.")

(defvar +my/mermaid--json nil "The config's JSON as the last theme made it.")

(defun +my/mermaid-theme-h ()
  "The config made from the new theme; changed, its file rewritten (if this
session wrote it) and `+my/mermaid-theme-hook' run."
  (let ((json (+my/mermaid-config-json)))
    (unless (equal json +my/mermaid--json)
      (setq +my/mermaid--json json)
      (when +my/mermaid--written
        (+my/mermaid-write-config))
      (run-hooks '+my/mermaid-theme-hook))))

;; Late: after the faces other hooks set.
(add-hook 'doom-load-theme-hook #'+my/mermaid-theme-h 90)
