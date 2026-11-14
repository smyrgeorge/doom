;;; $DOOMDIR/config/lsp/peek.el -*- lexical-binding: t; -*-
;; lsp-ui's peek, calmer and more informative. Loaded from config/lsp.el.

(defvar-local +my/peek--symbol nil "The symbol the peek is about.")

;;; Colours

;; The peek stands out from the code around it: an empty row above and below,
;; in the colour of its own top and bottom bars (the theme's peek header), and
;; a panel clearly darker than the editor (the preview more than the list).
;; Doom's themes made it barely darker. All from the theme, on every change.
(defun +my/peek-faces-h ()
  "The peek's colours (see above); soft selection and match colours (they're
bright blue in Doom's themes)."
  (when (and (facep 'lsp-ui-peek-selection) (fboundp 'doom-blend) (fboundp 'doom-color)
             (fboundp 'doom-darken))
    (let ((editor (face-background 'default nil t)))
      (when (and (stringp editor) (string-prefix-p "#" editor))
        (set-face-attribute 'lsp-ui-peek-peek nil :background (doom-darken editor 0.2))
        (set-face-attribute 'lsp-ui-peek-list nil :background (doom-darken editor 0.12))
        (set-face-attribute '+my/peek-separator nil :inherit 'unspecified
                            :background (let ((bar (face-background 'lsp-ui-peek-header nil t)))
                                          (if (and (stringp bar) (string-prefix-p "#" bar))
                                              bar
                                            (doom-darken editor 0.3)))
                            :extend t)))
    (let ((bg (face-background 'lsp-ui-peek-list nil t)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (set-face-attribute 'lsp-ui-peek-selection nil
                            :background (doom-blend (doom-color 'blue) bg 0.3)
                            :foreground 'unspecified :weight 'unspecified)
        (set-face-attribute 'lsp-ui-peek-highlight nil
                            :background (doom-blend (doom-color 'yellow) bg 0.25)
                            :foreground 'unspecified :box 'unspecified
                            :distant-foreground 'unspecified)
        ;; Dimmer than the code, but readable on the selection too.
        (set-face-attribute 'lsp-ui-peek-line-number nil
                            :foreground (face-foreground 'font-lock-comment-face nil t))))))

(after! lsp-ui-peek (+my/peek-faces-h))

(add-hook 'doom-load-theme-hook #'+my/peek-faces-h)

;;; What's listed

;; Usages without the declaration. (lsp-ui hands its first argument to
;; lsp-mode as the "exclude" flag, so ask lsp-mode directly.)
(defadvice! +my/peek-usages-a (&optional _include-declaration extra)
  "Find usages, the declaration left out (see above)."
  :override #'lsp-ui-peek-find-references
  (interactive)
  (lsp-ui-peek--find-xrefs (symbol-at-point) "textDocument/references"
                           (append extra (lsp--make-reference-params nil t))))

(defadvice! +my/peek-remember-symbol-a (input &rest _)
  :before #'lsp-ui-peek--find-xrefs
  ;; Plain: in Markdown the word came with its heading's face, in the title.
  (setq +my/peek--symbol (and input (substring-no-properties (format "%s" input)))))

;;; Height

(defun +my/peek--height (xrefs room)
  "The peek's height for XREFS (lsp-ui's, by file), ROOM rows below the
declaration's line: as tall as the list needs (files and usages), from
`+my/peek-min-height' to lsp-ui's height, but never more than ROOM less
the 3 rows around it (the separators, the footer), the minimum giving way.
Even, as lsp-ui wants it."
  (let* ((rows (+ 1 (length xrefs)
                  (cl-loop for file in xrefs sum (or (plist-get file :count) 0))))
         (wanted (max +my/peek-min-height
                      (min (default-value 'lsp-ui-peek-peek-height) (1+ rows))))
         (most (- room 3)))
    (max 2 (min (+ wanted (logand wanted 1))
                (- most (logand most 1))))))

;; lsp-ui makes room below the declaration by putting it on the window's row
;; 15, whatever the window: in a short one its last row, the peek below it off
;; screen (and lsp-ui's own test, by buffer lines, misses wrapped ones). Only
;; when the peek doesn't fit below it, the window scrolls so it just does.
(defadvice! +my/peek-fit-height-a (fn xrefs)
  "As tall as the list needs, within the usual bounds and the window, which
scrolls if the peek doesn't fit below the declaration (see above)."
  :around #'lsp-ui-peek--show
  (let* ((above (count-screen-lines (window-start) (line-beginning-position 2)))
         (room (- (window-body-height) above))
         (height (+my/peek--height xrefs (1- (window-body-height)))))
    (setq-local lsp-ui-peek-peek-height height)
    (prog1 (cl-letf (((symbol-function 'recenter) #'ignore))
             (funcall fn xrefs))
      (when (< room (+ height 3))
        (recenter (- (+ height 4)))))))

(defadvice! +my/peek-reset-height-a (&rest _)
  :after #'lsp-ui-peek--peek-hide
  (kill-local-variable 'lsp-ui-peek-peek-height))

;;; The function/class of each usage

(defun +my/peek--scope-at (pos)
  "The functions/classes around POS, outermost first, as \"Outer.inner\"."
  (save-excursion
    (goto-char pos)
    (let ((names
           (if (and (fboundp '+my/sticky--treesit-p) (+my/sticky--treesit-p))
               (let ((node (treesit-node-at (point))) names)
                 (while node
                   (when (+my/sticky--defun-node-p node)
                     (when-let* ((name (or (ignore-errors (treesit-defun-name node))
                                           (when-let* ((child (or (treesit-node-child-by-field-name node "name")
                                                                  (treesit-search-subtree
                                                                   node "\\`\\(simple_\\|type_\\)?identifier\\'"
                                                                   nil nil 1))))
                                             (treesit-node-text child t)))))
                       (push name names)))
                   (setq node (treesit-node-parent node)))
                 names)
             (when-let* ((name (ignore-errors (add-log-current-defun))))
               (list name)))))
      (if names
          (string-join names ".")
        (+my/peek--top-level-name)))))

(defun +my/peek--top-level-name ()
  "Outside functions/classes: the name the top-level statement at point
assigns or declares (e.g. a constant holding a big literal), if any."
  (when (and (fboundp '+my/sticky--treesit-p) (+my/sticky--treesit-p))
    (let ((root (treesit-buffer-root-node))
          (node (treesit-node-at (point))))
      (while (and node (treesit-node-parent node)
                  (not (treesit-node-eq (treesit-node-parent node) root)))
        (setq node (treesit-node-parent node)))
      (when-let* ((id (and node
                           (treesit-search-subtree
                            node
                            (lambda (n)
                              (and (string-match-p "identifier\\'" (treesit-node-type n))
                                   (string-match-p "assignment\\|declarat"
                                                   (or (treesit-node-type (treesit-node-parent n)) ""))))
                            nil nil 4))))
        (treesit-node-text id t)))))

;; lsp-ui reads the files with usages that aren't open without decoding them
;; (`insert-file-contents-literally'): in the preview an en dash showed as
;; \342\200\223, and any non-ASCII text (Greek...) as octal escapes. Read them as
;; Emacs opens files.
(defadvice! +my/peek-decode-files-a (fn file)
  "Read the files decoded (see above)."
  :around #'lsp-ui-peek--get-xrefs-in-file
  (cl-letf (((symbol-function 'insert-file-contents-literally)
             (lambda (filename &rest args)
               (apply #'insert-file-contents filename args))))
    (funcall fn file)))

;; lsp-ui reads each file with usages into a temporary buffer, without a major
;; mode (unless it fontifies everything): give it its mode, without hooks (no
;; language server starts), to tell which function each usage is in.
(defadvice! +my/peek-file-mode-a (filename)
  :after #'lsp-ui-peek--fontify-buffer
  (when (eq major-mode 'fundamental-mode)
    (make-local-variable 'delay-mode-hooks) ; as lsp-ui does (else a warning)
    (let ((buffer-file-name filename)
          (enable-local-variables nil)
          (inhibit-message t)
          (delay-mode-hooks t))
      (ignore-errors (set-auto-mode)))))

(defadvice! +my/peek-item-a (item)
  "Add to each usage its function/class (:scope) and the first line of its
preview (:first-line)."
  :filter-return #'lsp-ui-peek--xref-make-item
  (let ((line (plist-get item :line)))
    (when-let* ((scope (ignore-errors
                         (save-excursion
                           (goto-char (point-min))
                           (forward-line line)
                           (forward-char (min (or (plist-get item :column) 0)
                                              (- (line-end-position) (point))))
                           (+my/peek--scope-at (point))))))
      (setq item (plist-put item :scope scope)))
    ;; Where `lsp-ui-peek--extract-chunk-from-buffer' starts the preview.
    (plist-put item :first-line
               (max 1 (- (1+ line) (1- (/ lsp-ui-peek-peek-height 2)))))))

(defun +my/peek--fit (string width)
  "STRING cut or padded to WIDTH columns."
  (truncate-string-to-width string width nil ?\s "…"))

(defun +my/peek--fit-left (string width)
  "STRING cut from the left or padded to WIDTH columns: a function's own name
is its last part (\"…method ×3\")."
  (if (<= (string-width string) width)
      (+my/peek--fit string width)
    (let ((cut string))
      (while (> (string-width cut) (1- width))
        (setq cut (substring cut 1)))
      (+my/peek--fit (concat "…" cut) width))))

(defun +my/peek--row (parts &optional width)
  "A row of the list from PARTS, (NUMBER LABEL LABELS-WIDTH CODE): the line
number, the function column (as wide as the file's widest label,
LABELS-WIDTH, up to `+my/peek-scope-width'), the code. In WIDTH columns
\(nil: any) the function column gives way so the code shows 15 (it goes
under 4), and the code is cut to fit."
  (pcase-let* ((`(,number ,label ,labels-width ,code) parts)
               (wanted (min +my/peek-scope-width labels-width))
               (room (if width (- width (string-width number) 4 16) wanted))
               (scope-width (cond ((>= room wanted) wanted)
                                  ((>= room 4) room)
                                  (t 0)))
               (row (concat number "  "
                            (when (> scope-width 0)
                              (concat (propertize (+my/peek--fit-left label scope-width)
                                                  'face 'font-lock-function-name-face)
                                      "  ")))))
    (concat row (if width
                    (truncate-string-to-width code (max 0 (- width (string-width row))) nil nil "…")
                  code))))

(defun +my/peek--ref-lines (items)
  "The list's lines for ITEMS (one file's usages, in order): line number, the
function/class on the first usage of each (×N when it has several), the code.
Each keeps its parts (`+my/peek-row') to be laid out again for the pane."
  (let* ((runs (let (runs)                ; ((SCOPE . COUNT) ...) in order
                 (dolist (item items (nreverse runs))
                   (let ((scope (or (plist-get item :scope) "")))
                     (if (and runs (equal (caar runs) scope))
                         (cl-incf (cdar runs))
                       (push (cons scope 1) runs))))))
         (labels (mapcar (lambda (run)
                           (if (and (> (cdr run) 1) (not (string-empty-p (car run))))
                               (format "%s ×%d" (car run) (cdr run))
                             (car run)))
                         runs))
         (labels-width (apply #'max 0 (mapcar #'string-width labels)))
         (number-width (length (number-to-string
                                (1+ (apply #'max 0 (mapcar (lambda (i) (plist-get i :line)) items))))))
         (lines nil))
    (cl-loop for run in runs
             for label in labels
             do (dotimes (i (cdr run))
                  (let* ((item (pop items))
                         (parts (list (propertize (format (format "%%%dd" number-width)
                                                          (1+ (plist-get item :line)))
                                                  'face 'lsp-ui-peek-line-number)
                                      (if (= i 0) label "")
                                      labels-width
                                      (string-trim (plist-get item :summary)))))
                    (push (lsp-ui-peek--add-prop
                           `(lsp-ui-peek ,item file ,(plist-get item :file) +my/peek-row ,parts)
                           (+my/peek--row parts))
                          lines))))
    (nreverse lines)))

(defadvice! +my/peek-insert-xrefs-a (xrefs filename index)
  "List a file's usages in line order, with their functions (see above)."
  :override #'lsp-ui-peek--insert-xrefs
  (let ((items (sort (lsp-ui-peek--get-xrefs-in-file (cons filename xrefs))
                     (lambda (a b) (< (plist-get a :line) (plist-get b :line))))))
    (setq lsp-ui-peek--list (-flatten (-insert-at (1+ index) (+my/peek--ref-lines items)
                                                  lsp-ui-peek--list)))
    (lsp-ui-peek--add-prop '(xrefs nil))))

;;; Width

;; The peek is as wide as its pane, but lsp-ui's list was 60 columns whatever
;; the pane, its preview the rest: in a narrow pane the preview showed "..",
;; rows ran past the pane's edge (or on to more rows, in a buffer that wraps),
;; the footer was cut. Now each time it's drawn the list gets half the pane, at
;; most `lsp-ui-peek-list-width' (config/lsp.el), and in a pane narrower than
;; `+my/peek-preview-min-width' all of it, no preview; the function column
;; gives way to the code, the title and footer are fitted. It's drawn again
;; when the pane's size changes (a pane opened beside it...), not only at the
;; next key.
(defun +my/peek--preview-p ()
  "Whether the peek in the selected window shows its preview (see above)."
  (>= (window-text-width) +my/peek-preview-min-width))

(defun +my/peek--list-width ()
  "The list's width in the peek in the selected window (see above)."
  (if (+my/peek--preview-p)
      (min lsp-ui-peek-list-width (/ (window-text-width) 2))
    (1- (window-text-width))))

(defadvice! +my/peek-fit-width-a (fn &rest args)
  "Draw the peek for its pane's width (see above)."
  :around #'lsp-ui-peek--peek
  (let ((lsp-ui-peek-list-width (+my/peek--list-width)))
    (apply fn args)))

(defun +my/peek-redraw-h (window)
  "For the buffer-local `window-size-change-functions' of a buffer with a
peek: draw it again for WINDOW's new size (see above)."
  (with-current-buffer (window-buffer window)
    (when (and (bound-and-true-p lsp-ui-peek-mode)
               (overlayp lsp-ui-peek--overlay)
               (eq (overlay-get lsp-ui-peek--overlay 'window) window))
      (with-selected-window window
        (lsp-ui-peek--peek)))))

(defun +my/peek-watch-size-h ()
  "While a peek is open, draw it again when its pane's size changes."
  (if (bound-and-true-p lsp-ui-peek-mode)
      (add-hook 'window-size-change-functions #'+my/peek-redraw-h nil t)
    (remove-hook 'window-size-change-functions #'+my/peek-redraw-h t)))

(add-hook 'lsp-ui-peek-mode-hook #'+my/peek-watch-size-h)

;;; Header, preview, footer

(defun +my/peek--title (&optional width)
  "E.g. \" Usages of HOLD1 · 22 in 1 file\"; in WIDTH columns, the symbol cut
to fit (or left out, then the kind), never the counts."
  (let* ((kind (pcase lsp-ui-peek--method
                 ("textDocument/references" "Usages")
                 ("textDocument/definition" "Definitions")
                 ("textDocument/implementation" "Implementations")
                 (method (capitalize (replace-regexp-in-string "\\`.*/" "" method)))))
         (files (cl-count-if-not (lambda (s) (get-text-property 0 'lsp-ui-peek s))
                                 lsp-ui-peek--list))
         (head (concat " " kind))
         (of (if +my/peek--symbol (format " of %s" +my/peek--symbol) ""))
         (counts (format " · %d in %d file%s"
                         lsp-ui-peek--size-list files (if (= files 1) "" "s")))
         (room (and width (- width (string-width head) (string-width counts)))))
    (cond ((or (null width) (>= room (string-width of))) (concat head of counts))
          ((>= room 6) (concat head (truncate-string-to-width of room nil nil "…") counts))
          ((>= room 0) (concat head counts))
          (t (concat " " (string-remove-prefix " · " counts))))))

(defun +my/peek--preview (src)
  "The preview (SRC: header, then lines) with line numbers, the usage's line
highlighted, cut to the peek's height around it."
  (let* ((xref (or (lsp-ui-peek--get-selection) lsp-ui-peek--last-xref))
         (first (plist-get xref :first-line))
         (usage (and (plist-get xref :line) (1+ (plist-get xref :line))))
         (lines (cdr src))
         (rows (1- lsp-ui-peek-peek-height)))
    (if (not (and first usage))
        src
      (let* ((index (- usage first))
             (start (max 0 (min (- index (/ rows 2)) (- (length lines) rows))))
             (shown (seq-take (nthcdr start lines) rows))
             ;; As wide as the last line shown's number.
             (width (length (number-to-string (+ first start (length shown) -1))))
             (current (face-background 'hl-line nil t)))
        (cons (concat " " (lsp-ui--workspace-path (plist-get xref :file))
                      ":" (number-to-string usage))
              (cl-loop for line in shown
                       for n from (+ first start)
                       collect (let ((string (concat (propertize (format (format "%%%dd " width) n)
                                                                 'face (if (= n usage)
                                                                           'line-number-current-line
                                                                         'line-number))
                                                     line)))
                                 (when (and (= n usage) current)
                                   (add-face-text-property 0 (length string)
                                                           `(:background ,current) nil string))
                                 string)))))))

(defadvice! +my/peek-frame-a (args)
  "The preview numbered (none in a narrow pane), the title, the list's rows,
laid out for the pane (see Width)."
  :filter-args #'lsp-ui-peek--peek-new
  (pcase-let ((`(,src1 ,src2) args)
              ;; Where lsp-ui cuts the list's rows (with "..").
              (width (- lsp-ui-peek-list-width 2)))
    (list (if (+my/peek--preview-p)
              (+my/peek--preview src1)
            (make-list (length src1) ""))
          (cons (+my/peek--title width)
                (mapcar (lambda (row)
                          (if-let* ((parts (get-text-property 0 '+my/peek-row row)))
                              (+my/peek--row parts width)
                            row))
                        (cdr src2))))))

(defconst +my/peek--keys
  '(("j/k" . "next/previous") ("C-j/C-k" . "file") ("RET" . "open")
    ("M-RET" . "other window") ("Esc" . "close"))
  "The peek's keys, as its footer lists them.")

(defadvice! +my/peek-footer-a ()
  "The keys, instead of an empty bar: as many as the pane has room for."
  :override #'lsp-ui-peek--make-footer
  (let ((text ""))
    (cl-loop for (key . action) in +my/peek--keys
             for item = (concat (if (string-empty-p text) "  " "   ") key "  " action)
             while (< (string-width (concat text item)) (window-text-width))
             do (setq text (concat text item)))
    (list (concat (propertize text 'face 'lsp-ui-peek-footer)
                  (propertize " " 'face 'lsp-ui-peek-footer
                              'display '(space :align-to (- right-fringe 0)))
                  (propertize "\n" 'face 'lsp-ui-peek-footer)))))

;;; Separators

(defun +my/peek--separator ()
  "An empty row across the window (see Colours)."
  (concat (propertize " " 'face '+my/peek-separator
                      'display '(space :align-to (- right-fringe 1)))
          (propertize "\n" 'face '+my/peek-separator)))

(defadvice! +my/peek-separators-a (&rest _)
  "An empty row above and below the peek (built anew for each move in it)."
  :after #'lsp-ui-peek--peek-new
  (when (overlayp lsp-ui-peek--overlay)
    (overlay-put lsp-ui-peek--overlay 'after-string
                 (concat (+my/peek--separator)
                         (overlay-get lsp-ui-peek--overlay 'after-string)
                         (+my/peek--separator)))))

;;; Fix

;; Closing the peek hides it twice, the second time with its overlay already
;; gone, and Doom's indent-guides module redraws the bars under that overlay
;; without checking: "Error running timer `lsp-ui-peek--disable':
;; (wrong-type-argument overlayp nil)". Only redraw while there's an overlay.
(defadvice! +my/indent-guides-peek-guard-a (fn &rest args)
  :around #'+indent-guides--restore-after-lsp-ui-peek-a
  (when (overlayp (bound-and-true-p lsp-ui-peek--overlay))
    (apply fn args)))
