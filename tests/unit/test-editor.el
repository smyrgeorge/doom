;;; tests/unit/test-editor.el -*- lexical-binding: t; -*-
;; config/editor.el: Cmd+B (declaration or usages), Cmd+[ / Cmd+] (back /
;; forward), M-[ / M-] (buffers, GUI only), SPC c ~ (case styles), rainbow
;; brackets, the right margin, the current line and the selection across
;; wrapped rows, the tree-sitter cache, highlighting after the first display.

(defvar doom-disabled-packages nil)     ; Doom's `use-package!' reads it
(+test-load "config/editor")

;; ====== HELPERS ======

(defmacro +test-editor--visiting (name content &rest body)
  "BODY in a buffer visiting NAME (in the temp folder) with CONTENT, killed
after. No version control (nothing runs git)."
  (declare (indent 2))
  `(let* ((vc-handled-backends nil)
          (file (+test-file ,name ,content))
          (buffer (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (when (buffer-live-p buffer)
         (let ((kill-buffer-query-functions nil))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(defmacro +test-editor--with-advice (symbol how fn &rest body)
  "BODY with FN advised (HOW) innermost on SYMBOL: under the config's advice."
  (declare (indent 3))
  `(let ((advice ,fn))
     (advice-add ,symbol ,how advice '((depth . 100)))
     (unwind-protect (progn ,@body)
       (advice-remove ,symbol advice))))

(defun +test-editor--prefixed-lines (n &optional prefix)
  "N lines \"line I\", each with PREFIX (default two spaces) as its wrap and
line prefix (as Doom's word wrap puts them)."
  (let ((prefix (or prefix "  ")))
    (mapconcat (lambda (i)
                 (propertize (format "line %d\n" i)
                             'wrap-prefix prefix 'line-prefix prefix))
               (number-sequence 1 n) "")))

(defun +test-editor--face-has (face prop)
  "Non-nil if FACE (a face, a list of faces or attributes) includes PROP."
  (or (eq face prop) (and (listp face) (memq prop face))))

;; ====== KEYS ======

(ert-deftest editor/keys-global ()
  "Cmd+B, Cmd+[ and Cmd+] in the global map."
  (should (eq (lookup-key global-map (kbd "s-b")) #'+my/goto-declaration-or-usages))
  (should (eq (lookup-key global-map (kbd "s-[")) #'better-jumper-jump-backward))
  (should (eq (lookup-key global-map (kbd "s-]")) #'better-jumper-jump-forward)))

(ert-deftest editor/keys-in-every-evil-state ()
  "No evil state shadows them (code, normal / insert / visual)."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "code.el" "(foo bar)\n" #'emacs-lisp-mode))
    (dolist (state '(normal insert visual emacs))
      (evil-change-state state)
      (should (eq (key-binding (kbd "s-b")) #'+my/goto-declaration-or-usages))
      (should (eq (key-binding (kbd "s-[")) #'better-jumper-jump-backward))
      (should (eq (key-binding (kbd "s-]")) #'better-jumper-jump-forward)))))

(ert-deftest editor/key-case-cycle-on-leader ()
  (should (eq (lookup-key doom-leader-map (kbd "c ~")) #'string-inflection-all-cycle))
  ;; Autoloaded (`:commands'): string-inflection loads on first use.
  (should (fboundp 'string-inflection-all-cycle))
  (should (commandp 'string-inflection-all-cycle)))

(ert-deftest editor/gui-only-menu-item ()
  "A menu item whose filter gives the command in the GUI, nothing in a terminal."
  (let* ((item (+my/gui-only #'previous-buffer))
         (filter (plist-get (nthcdr 3 item) :filter)))
    (should (eq (car item) 'menu-item))
    (should (equal (nth 1 item) ""))
    (should (eq (nth 2 item) #'previous-buffer))
    (should (functionp filter))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (should (eq (funcall filter #'previous-buffer) #'previous-buffer)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
      (should-not (funcall filter #'previous-buffer)))))

(ert-deftest editor/buffer-keys-gui-only ()
  "M-[ / M-]: previous / next buffer in the GUI; unbound in a terminal, where
they're ESC [ / ESC ], the start of escape sequences."
  (+test-with-reset
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (should (eq (key-binding (kbd "M-[")) #'previous-buffer))
      (should (eq (key-binding (kbd "M-]")) #'next-buffer)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
      (should-not (key-binding (kbd "M-[")))
      (should-not (key-binding (kbd "M-]")))
      (should-not (key-binding [27 ?\[]))
      (should-not (key-binding [27 ?\]])))))

(ert-deftest editor/buffer-keys-switch-buffers ()
  (+test-with-reset
    (let ((a (+test-buffer "A")) (b (+test-buffer "B")))
      (switch-to-buffer a)
      (switch-to-buffer b)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (call-interactively (key-binding (kbd "M-[")))
        (should (eq (current-buffer) a))
        (call-interactively (key-binding (kbd "M-]")))
        (should (eq (current-buffer) b))))))

;; ====== BACK / FORWARD ======

(ert-deftest editor/back-and-forward-through-jumps ()
  "Cmd+[ goes back to where the cursor jumped from, Cmd+] forward again."
  (require 'better-jumper)
  (+test-with-reset
    (better-jumper-mode 1)
    (unwind-protect
        (+test-editor--visiting "jumps.txt" (mapconcat #'number-to-string
                                                       (number-sequence 1 50) "\n")
          (switch-to-buffer (current-buffer))
          (goto-char (point-min))
          (forward-line 4)
          (let ((from (point)))
            (better-jumper-set-jump)
            (goto-char (point-max))
            (let ((to (point)))
              (call-interactively (lookup-key global-map (kbd "s-[")))
              (should (= (point) from))
              (call-interactively (lookup-key global-map (kbd "s-]")))
              (should (= (point) to)))))
      (better-jumper-mode -1))))

;; ====== CASE STYLE (SPC c ~) ======

(ert-deftest editor/case-cycle-order ()
  "snake_case → UPPER_CASE → PascalCase → camelCase → kebab-case, and on
round to snake_case again."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "case.el" "foo_bar" #'emacs-lisp-mode))
    (let ((cmd (lookup-key doom-leader-map (kbd "c ~")))
          (seen nil))
      (dotimes (_ 4)
        (goto-char (point-min))
        (call-interactively cmd)
        (push (buffer-string) seen))
      (should (equal (nreverse seen) '("FOO_BAR" "FooBar" "fooBar" "foo-bar")))
      ;; Back to the start eventually (string-inflection adds Foo_Bar).
      (let ((n 0))
        (while (and (< n 4) (not (equal (buffer-string) "foo_bar")))
          (goto-char (point-min))
          (call-interactively cmd)
          (cl-incf n))
        (should (equal (buffer-string) "foo_bar"))))))

(ert-deftest editor/case-cycle-word-at-point-only ()
  (+test-with-reset
    (switch-to-buffer (+test-buffer "case2.el" "(setq my_var other_var)" #'emacs-lisp-mode))
    (search-forward "my_")
    (call-interactively (lookup-key doom-leader-map (kbd "c ~")))
    (should (equal (buffer-string) "(setq MY_VAR other_var)"))))

;; ====== RAINBOW BRACKETS ======

(ert-deftest editor/rainbow-in-code-only ()
  (should (memq 'rainbow-delimiters-mode prog-mode-hook))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (bound-and-true-p rainbow-delimiters-mode)))
  (with-temp-buffer
    (text-mode)
    (should-not (bound-and-true-p rainbow-delimiters-mode))))

(ert-deftest editor/rainbow-colours-by-depth ()
  "(), [] and {} get a colour per nesting depth, matching pairs alike."
  (with-temp-buffer
    (js-mode)
    (should (bound-and-true-p rainbow-delimiters-mode))
    (insert "f(a, [b, {c: (d)}]);")
    (font-lock-mode 1)
    (font-lock-ensure)
    (cl-flet ((depth-at (char)
                (goto-char (point-min))
                (search-forward char)
                (let ((face (get-text-property (match-beginning 0) 'face)))
                  (cl-loop for depth from 1 to 9
                           when (+test-editor--face-has
                                 face (intern (format "rainbow-delimiters-depth-%d-face" depth)))
                           return depth))))
      (should (eql (depth-at "(") 1))
      (should (eql (depth-at "[") 2))
      (should (eql (depth-at "{") 3))
      (should (eql (depth-at "(d") 4))
      (should (eql (depth-at ")") 4))
      (should (eql (depth-at "}") 3))
      (should (eql (depth-at "]") 2))
      (should (eql (depth-at ");") 1)))))

;; ====== RIGHT MARGIN ======

(ert-deftest editor/right-margin-hooks ()
  (dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
    (should (memq #'+my/right-margin-h (symbol-value hook)))))

(ert-deftest editor/right-margin-in-files-of-code-text-config ()
  (+test-editor--visiting "margin/code.el" "(foo)\n"
    (should (derived-mode-p 'prog-mode))
    (should display-fill-column-indicator-mode)
    ;; At `fill-column' (the default column: t).
    (should (eq display-fill-column-indicator-column t)))
  (+test-editor--visiting "margin/notes.txt" "text\n"
    (should (derived-mode-p 'text-mode))
    (should display-fill-column-indicator-mode))
  (+test-editor--visiting "margin/app.conf" "a = b\n"
    (should (derived-mode-p 'conf-mode))
    (should display-fill-column-indicator-mode)))

(ert-deftest editor/right-margin-not-without-a-file ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not display-fill-column-indicator-mode))
  (with-temp-buffer
    (text-mode)
    (should-not display-fill-column-indicator-mode)))

(ert-deftest editor/right-margin-not-in-other-modes ()
  "A file in neither a code, text nor configuration mode gets no line."
  (+test-editor--visiting "margin/data.zzunknown" "data\n"
    (should (eq major-mode 'fundamental-mode))
    (should-not display-fill-column-indicator-mode)))

(ert-deftest editor/right-margin-editorconfig-hook-registered ()
  (require 'editorconfig)
  (should (memq #'+my/right-margin-editorconfig-h editorconfig-after-apply-functions)))

(ert-deftest editor/right-margin-editorconfig-off ()
  "max_line_length = off (any case) removes the line; a number or nothing
keeps it."
  (require 'editorconfig)
  (cl-flet ((after (value)
              (with-temp-buffer
                (display-fill-column-indicator-mode 1)
                (let ((props (make-hash-table)))
                  (when value (puthash 'max_line_length value props))
                  (+my/right-margin-editorconfig-h props))
                display-fill-column-indicator-mode)))
    (should-not (after "off"))
    (should-not (after "OFF"))
    (should-not (after "Off"))
    (should (after "100"))
    (should (after nil))
    (should (after "offf"))
    (should (after 'off))))

(ert-deftest editor/right-margin-editorconfig-real-files ()
  "A project's .editorconfig moves the line (max_line_length 100: fill-column
100, which the line follows) or removes it (off)."
  (require 'editorconfig)
  (let ((editorconfig-get-properties-function #'editorconfig-core-get-properties-hash)
        (was editorconfig-mode))
    (+test-file "ec/.editorconfig"
                "root = true\n\n[*.el]\nmax_line_length = 100\n\n[*.txt]\nmax_line_length = off\n")
    (editorconfig-mode 1)
    (unwind-protect
        (progn
          (+test-editor--visiting "ec/code.el" "(foo)\n"
            (should (= fill-column 100))
            (should display-fill-column-indicator-mode))
          (+test-editor--visiting "ec/notes.txt" "text\n"
            (should-not display-fill-column-indicator-mode)))
      (editorconfig-mode (if was 1 -1)))))

(ert-deftest editor/right-margin-faint-as-line-numbers ()
  "The line is coloured like the line numbers, again when the theme changes."
  (let ((ln (face-attribute 'line-number :foreground))
        (fci (face-attribute 'fill-column-indicator :foreground)))
    (unwind-protect
        (progn
          (set-face-attribute 'line-number nil :foreground "#123456")
          (+my/right-margin-face-h)
          (should (equal (face-attribute 'fill-column-indicator :foreground) "#123456"))
          (should (memq #'+my/right-margin-face-h doom-load-theme-hook))
          (set-face-attribute 'line-number nil :foreground "#abcdef")
          (run-hooks 'doom-load-theme-hook)
          (should (equal (face-attribute 'fill-column-indicator :foreground) "#abcdef")))
      (set-face-attribute 'line-number nil :foreground ln)
      (set-face-attribute 'fill-column-indicator nil :foreground fci))))

;; ====== CURRENT LINE ACROSS WRAPPED ROWS ======

(ert-deftest editor/prefix-copy-in-face ()
  (should-not (+my/hl-line--prefix nil 'hl-line))
  (let* ((prefix (propertize "  " 'face 'bold))
         (copy (+my/hl-line--prefix prefix 'hl-line)))
    (should (equal copy "  "))
    (should-not (eq copy prefix))
    (should (+test-editor--face-has (get-text-property 0 'face copy) 'hl-line))
    (should (+test-editor--face-has (get-text-property 1 'face copy) 'hl-line))
    ;; The text's own prefix is left as it was.
    (should (eq (get-text-property 0 'face prefix) 'bold)))
  ;; A display spec, e.g. (space :width 4).
  (let ((copy (+my/hl-line--prefix '(space :width 4) 'region)))
    (should (equal copy " "))
    (should (equal (get-text-property 0 'display copy) '(space :width 4)))
    (should (eq (get-text-property 0 'face copy) 'region))))

(ert-deftest editor/hl-line-prefixes-ignores-non-overlays ()
  (should-not (+my/hl-line-prefixes nil))
  (should-not (+my/hl-line-prefixes 'not-an-overlay))
  (with-temp-buffer
    (insert "text\n")
    (let ((ov (make-overlay 1 3)))
      (delete-overlay ov)
      (should-not (+my/hl-line-prefixes ov)))))

(ert-deftest editor/hl-line-prefixes-from-text ()
  (with-temp-buffer
    (insert (+test-editor--prefixed-lines 3 "    "))
    (goto-char (point-min))
    (forward-line 1)
    (let ((ov (make-overlay (line-beginning-position) (line-beginning-position 2))))
      (overlay-put ov 'face 'hl-line)
      (+my/hl-line-prefixes ov)
      (should (equal (overlay-get ov 'wrap-prefix) "    "))
      (should (equal (overlay-get ov 'line-prefix) "    "))
      (should (+test-editor--face-has (get-text-property 0 'face (overlay-get ov 'wrap-prefix))
                                      'hl-line))
      (should (+test-editor--face-has (get-text-property 0 'face (overlay-get ov 'line-prefix))
                                      'hl-line)))))

(ert-deftest editor/hl-line-prefixes-from-buffer-variables ()
  "Without text properties, the buffer's `wrap-prefix' / `line-prefix'."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (setq-local wrap-prefix "  ")
    (setq-local line-prefix '(space :width 2))
    (let ((ov (make-overlay 1 5)))
      (overlay-put ov 'face 'hl-line)
      (+my/hl-line-prefixes ov)
      (should (equal (overlay-get ov 'wrap-prefix) "  "))
      (should (equal (get-text-property 0 'display (overlay-get ov 'line-prefix))
                     '(space :width 2))))))

(ert-deftest editor/hl-line-prefixes-no-prefix-no-change ()
  (with-temp-buffer
    (insert "plain\nlines\n")
    (let ((ov (make-overlay 1 7)))
      (overlay-put ov 'face 'hl-line)
      (+my/hl-line-prefixes ov)
      (should-not (overlay-get ov 'wrap-prefix))
      (should-not (overlay-get ov 'line-prefix)))))

(ert-deftest editor/hl-line-prefixes-only-whole-lines ()
  "A highlight over part of the line (Doom's dashboard menu item) keeps its
look: no prefixes."
  (with-temp-buffer
    (insert (+test-editor--prefixed-lines 2))
    (let ((ov (make-overlay 1 4)))
      (overlay-put ov 'face 'hl-line)
      (+my/hl-line-prefixes ov)
      (should-not (overlay-get ov 'wrap-prefix))
      (should-not (overlay-get ov 'line-prefix)))))

(ert-deftest editor/hl-line-prefixes-cached ()
  "Done again only when the line, its prefixes or the face changed."
  (with-temp-buffer
    (insert (+test-editor--prefixed-lines 3))
    (let ((ov (make-overlay 1 8)))
      (overlay-put ov 'face 'hl-line)
      (+my/hl-line-prefixes ov)
      (overlay-put ov 'wrap-prefix "marker")
      (+my/hl-line-prefixes ov)                         ; nothing changed
      (should (equal (overlay-get ov 'wrap-prefix) "marker"))
      (overlay-put ov 'face 'region)                    ; the face changed
      (+my/hl-line-prefixes ov)
      (should (equal (overlay-get ov 'wrap-prefix) "  "))
      (should (+test-editor--face-has (get-text-property 0 'face (overlay-get ov 'wrap-prefix))
                                      'region))
      (overlay-put ov 'wrap-prefix "marker")
      (move-overlay ov 8 15)                            ; another line
      (+my/hl-line-prefixes ov)
      (should (equal (overlay-get ov 'wrap-prefix) "  ")))))

(ert-deftest editor/hl-line-advice-installed ()
  (should (advice-member-p '+my/hl-line-move-prefixes-a 'hl-line-move))
  (should (advice-member-p '+my/hl-line-window-prefixes-a 'global-hl-line-window-redisplay)))

(ert-deftest editor/hl-line-mode-overlay-gets-prefixes ()
  "hl-line's overlay (moved by `hl-line-move') carries the line's prefixes."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "hl" (+test-editor--prefixed-lines 5)))
    (unwind-protect
        (progn
          (hl-line-mode 1)
          (forward-line 2)
          (hl-line-highlight)
          (let ((wrap (overlay-get hl-line-overlay 'wrap-prefix)))
            (should (equal wrap "  "))
            (should (+test-editor--face-has (get-text-property 0 'face wrap) hl-line-face))))
      (hl-line-mode -1))))

(ert-deftest editor/global-hl-line-window-overlay-gets-prefixes ()
  "With `global-hl-line-sticky-flag' `window' (Doom's), the overlay kept in
the window parameter carries them too."
  (require 'hl-line)
  (+test-with-reset
    (switch-to-buffer (+test-buffer "ghl" (+test-editor--prefixed-lines 5)))
    (forward-line 1)
    (let ((global-hl-line-buffers t))
      (global-hl-line-window-redisplay (selected-window))
      (let ((ov (window-parameter (selected-window) 'hl-line-overlay)))
        (unwind-protect
            (progn
              (should (overlayp ov))
              (should (equal (overlay-get ov 'wrap-prefix) "  "))
              (should (+test-editor--face-has
                       (get-text-property 0 'face (overlay-get ov 'wrap-prefix))
                       (overlay-get ov 'face))))
          (when (overlayp ov) (delete-overlay ov))
          (set-window-parameter (selected-window) 'hl-line-overlay nil))))))

;; ====== SELECTION ACROSS WRAPPED ROWS ======

(defmacro +test-editor--with-selection (content &rest body)
  "BODY in the selected window on a buffer with CONTENT, the region usable."
  (declare (indent 1))
  `(+test-with-reset
     (switch-to-buffer (+test-buffer "sel" ,content))
     (evil-emacs-state)
     (let ((transient-mark-mode t)
           (highlight-nonselected-windows nil))
       (unwind-protect (progn ,@body)
         (deactivate-mark)
         (redisplay--update-region-highlight (selected-window))
         (set-window-parameter (selected-window) '+my/region-prefixes-key nil)))))

(defun +test-editor--select (beg end)
  "Select BEG..END, as redisplay then highlights it."
  (goto-char end)
  (set-mark beg)
  (activate-mark)
  (redisplay--update-region-highlight (selected-window)))

(defun +test-editor--region-overlays ()
  (window-parameter (selected-window) '+my/region-prefixes))

(ert-deftest editor/region-prefix-advice-installed ()
  (should (advice-member-p '+my/region-prefixes-a 'redisplay--update-region-highlight)))

(ert-deftest editor/region-prefixes-one-per-selected-line ()
  (+test-editor--with-selection (+test-editor--prefixed-lines 6)
    (let* ((beg (save-excursion (goto-char (point-min)) (forward-line 1) (+ (point) 2)))
           (end (save-excursion (goto-char (point-min)) (forward-line 3) (+ (point) 3))))
      (+test-editor--select beg end)
      (let ((ovs (sort (copy-sequence (+test-editor--region-overlays))
                       (lambda (a b) (< (overlay-start a) (overlay-start b))))))
        (should (= (length ovs) 3))
        ;; Over its part of the selection: from the selection's start on the
        ;; first line, to its end on the last.
        (should (= (overlay-start (nth 0 ovs)) beg))
        (should (= (overlay-end (nth 2 ovs)) end))
        (should (= (overlay-start (nth 1 ovs))
                   (save-excursion (goto-char beg) (line-beginning-position 2))))
        (dolist (ov ovs)
          (should (eq (overlay-get ov 'window) (selected-window)))
          (should (equal (overlay-get ov 'priority) '(nil . 110)))
          (should (equal (overlay-get ov 'wrap-prefix) "  "))
          (should (+test-editor--face-has (get-text-property 0 'face (overlay-get ov 'wrap-prefix))
                                          'region))
          (should (+test-editor--face-has (get-text-property 0 'face (overlay-get ov 'line-prefix))
                                          'region)))))))

(ert-deftest editor/region-prefixes-skip-lines-without-prefixes ()
  (+test-editor--with-selection (concat "plain one\n" (+test-editor--prefixed-lines 1) "plain two\n")
    (+test-editor--select (point-min) (point-max))
    (let ((ovs (+test-editor--region-overlays)))
      (should (= (length ovs) 1))
      (should (= (overlay-start (car ovs)) (save-excursion (goto-char (point-min))
                                                           (line-beginning-position 2)))))))

(ert-deftest editor/region-prefixes-from-buffer-variables ()
  (+test-editor--with-selection "one\ntwo\nthree\n"
    (setq-local wrap-prefix "   ")
    (+test-editor--select (point-min) (point-max))
    (should (= (length (+test-editor--region-overlays)) 3))
    (should (equal (overlay-get (car (+test-editor--region-overlays)) 'wrap-prefix) "   "))))

(ert-deftest editor/region-prefixes-removed-with-the-selection ()
  (+test-editor--with-selection (+test-editor--prefixed-lines 4)
    (+test-editor--select (point-min) (point-max))
    (let ((ovs (+test-editor--region-overlays)))
      (should (= (length ovs) 4))
      (deactivate-mark)
      (redisplay--update-region-highlight (selected-window))
      (should-not (+test-editor--region-overlays))
      (dolist (ov ovs) (should-not (overlay-buffer ov))))))

(ert-deftest editor/region-prefixes-empty-selection ()
  (+test-editor--with-selection (+test-editor--prefixed-lines 4)
    (+test-editor--select 3 3)
    (should-not (+test-editor--region-overlays))))

(ert-deftest editor/region-prefixes-cached-and-reused ()
  "Redone only when the selection, scroll or text changed; the overlays are
reused, never piling up."
  (+test-editor--with-selection (+test-editor--prefixed-lines 8)
    (+test-editor--select (point-min) (save-excursion (goto-char (point-min))
                                                      (forward-line 3) (point)))
    (let ((ovs (+test-editor--region-overlays)))
      (should (= (length ovs) 3))
      (redisplay--update-region-highlight (selected-window))  ; same: kept
      (should (eq (+test-editor--region-overlays) ovs))
      ;; Grown by a line: the same overlays, plus one.
      (+test-editor--select (point-min) (save-excursion (goto-char (point-min))
                                                        (forward-line 4) (point)))
      (let ((new (+test-editor--region-overlays)))
        (should (= (length new) 4))
        (dolist (ov ovs) (should (memq ov new))))
      ;; The text changed (word wrap adds prefixes as lines are shown).
      (let ((before (+test-editor--region-overlays)))
        (save-excursion
          (goto-char (point-max))
          (insert "x"))
        (+my/region-prefixes (selected-window))
        (should (= (length (+test-editor--region-overlays)) 4))
        (should-not (eq (+test-editor--region-overlays) before)))
      ;; Only the overlays in use exist in the buffer.
      (should (= (length (seq-filter (lambda (ov) (overlay-get ov 'priority))
                                     (overlays-in (point-min) (point-max))))
                 ;; The region's own overlay, and ours.
                 (1+ (length (+test-editor--region-overlays))))))))

(ert-deftest editor/region-prefixes-only-on-screen ()
  "A selection longer than the window: no further than the screen."
  (+test-editor--with-selection (+test-editor--prefixed-lines 200)
    (set-window-start (selected-window) (point-min))
    (+test-editor--select (point-min) (point-max))
    (should (= (length (+test-editor--region-overlays))
               (window-body-height (selected-window))))))

(ert-deftest editor/region-prefixes-from-the-window-start ()
  "A selection starting above the screen: from the first line shown."
  (+test-editor--with-selection (+test-editor--prefixed-lines 200)
    (let ((start (save-excursion (goto-char (point-min)) (forward-line 50) (point))))
      (+test-editor--select (point-min) (save-excursion (goto-char start) (forward-line 5) (point)))
      (set-window-start (selected-window) start)
      (+my/region-prefixes (selected-window))
      (let ((ovs (+test-editor--region-overlays)))
        (should (= (length ovs) 5))
        (should (= (apply #'min (mapcar #'overlay-start ovs)) start))))))

(ert-deftest editor/region-prefixes-other-buffer-region-ignored ()
  "The window's region overlay in another buffer: nothing done."
  (+test-editor--with-selection (+test-editor--prefixed-lines 4)
    (let ((other (+test-buffer "other" (+test-editor--prefixed-lines 4)))
          (ov nil))
      (with-current-buffer other
        (setq ov (make-overlay 1 20)))
      (overlay-put ov 'face 'region)
      (set-window-parameter (selected-window) 'internal-region-overlay ov)
      (+my/region-prefixes (selected-window))
      (should-not (+test-editor--region-overlays))
      (set-window-parameter (selected-window) 'internal-region-overlay nil)
      (delete-overlay ov))))

(ert-deftest editor/region-prefixes-dead-window ()
  (+test-with-reset
    (let ((window (split-window)))
      (delete-window window)
      (should-not (+my/region-prefixes-a window)))))

;; ====== GO TO DECLARATION OR USAGES (Cmd+B) ======

;; A backend whose definitions a test chooses, and one standing for lsp-mode's.
(defvar +test-editor--definitions nil
  "What the test backends return as definitions (a function of the id).")

(cl-defmethod xref-backend-identifier-at-point ((_ (eql '+test-editor)))
  (thing-at-point 'symbol t))

(cl-defmethod xref-backend-definitions ((_ (eql '+test-editor)) id)
  (funcall +test-editor--definitions id))

(unless (featurep 'lsp-mode)
  (cl-defmethod xref-backend-identifier-at-point ((_ (eql 'xref-lsp)))
    (thing-at-point 'symbol t))
  (cl-defmethod xref-backend-definitions ((_ (eql 'xref-lsp)) id)
    (funcall +test-editor--definitions id)))

(defmacro +test-editor--with-backend (backend definitions &rest body)
  "BODY with BACKEND the buffer's xref backend, DEFINITIONS (a function of
the id) its definitions."
  (declare (indent 2))
  `(let ((+test-editor--definitions ,definitions))
     (setq-local xref-backend-functions (list (lambda () ,backend)))
     ,@body))

(defun +test-editor--code ()
  "Some code: a declaration on line 2, a use on line 4."
  "// code\nfun answer() = 42\n\nval x = answer()\n")

(defun +test-editor--goto (string &optional nth)
  "Point on the NTH (default 1st) STRING in the buffer."
  (goto-char (point-min))
  (search-forward string nil nil (or nth 1))
  (goto-char (match-beginning 0)))

(defun +test-editor--here (line column)
  "A definition in this buffer's file at LINE, COLUMN."
  (xref-make "answer" (xref-make-file-location buffer-file-name line column)))

(ert-deftest editor/at-declaration-on-the-declaration ()
  (+test-editor--visiting "decl/a.kt" (+test-editor--code)
    (+test-editor--with-backend '+test-editor (lambda (_) (list (+test-editor--here 2 4)))
      (+test-editor--goto "answer")
      (should (+my/at-declaration-p))
      ;; Anywhere on the name.
      (forward-char 5)
      (should (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-not-on-a-use ()
  (+test-editor--visiting "decl/b.kt" (+test-editor--code)
    (+test-editor--with-backend '+test-editor (lambda (_) (list (+test-editor--here 2 4)))
      (+test-editor--goto "answer" 2)
      (should-not (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-same-line-other-symbol ()
  "A declaration on this line but not where the symbol at point is."
  (+test-editor--visiting "decl/c.kt" "fun answer() = other()\nfun other() = 1\n"
    (+test-editor--with-backend '+test-editor (lambda (_) (list (+test-editor--here 1 4)))
      (+test-editor--goto "other")
      (should-not (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-elsewhere-never-opens-files ()
  "Declarations in other files (even on the same line number) aren't looked
at closer: their files stay closed."
  (let ((other (+test-file "decl/other.kt" "// other\nfun answer() = 42\n")))
    (+test-editor--visiting "decl/d.kt" (+test-editor--code)
      (+test-editor--with-backend
          '+test-editor (lambda (_) (list (xref-make "answer" (xref-make-file-location other 2 4))))
        (+test-editor--goto "answer")
        (should-not (+my/at-declaration-p))
        (should-not (get-file-buffer other))))))

(ert-deftest editor/at-declaration-one-of-several ()
  (let ((other (+test-file "decl/other2.kt" "fun answer() = 1\n")))
    (+test-editor--visiting "decl/e.kt" (+test-editor--code)
      (+test-editor--with-backend
          '+test-editor (lambda (_) (list (xref-make "answer" (xref-make-file-location other 1 4))
                                          (+test-editor--here 2 4)))
        (+test-editor--goto "answer")
        (should (+my/at-declaration-p))))))

(ert-deftest editor/at-declaration-no-symbol ()
  (+test-editor--visiting "decl/f.kt" "   \n"
    (+test-editor--with-backend '+test-editor (lambda (_) (error "Not called"))
      (should-not (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-no-definitions ()
  "No definitions known: not at the declaration (the jump falls back)..."
  (+test-editor--visiting "decl/g.kt" (+test-editor--code)
    (+test-editor--with-backend '+test-editor (lambda (_) nil)
      (+test-editor--goto "answer")
      (should-not (+my/at-declaration-p)))
    ;; ...also when asking fails.
    (+test-editor--with-backend '+test-editor (lambda (_) (error "Server error"))
      (+test-editor--goto "answer")
      (should-not (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-lsp-knows-none ()
  "With a language server knowing no declaration (a Markdown heading), list
the usages: counts as the declaration."
  (+test-editor--visiting "decl/doc.md" "# Heading\n\nSee [the heading](#heading).\n"
    (+test-editor--with-backend 'xref-lsp (lambda (_) nil)
      (+test-editor--goto "Heading")
      (should (+my/at-declaration-p)))
    (+test-editor--with-backend 'xref-lsp (lambda (_) (error "No definition"))
      (+test-editor--goto "Heading")
      (should (+my/at-declaration-p)))
    ;; A server that knows one elsewhere: a jump.
    (let ((other (+test-file "decl/other.md" "# Heading\n")))
      (+test-editor--with-backend
          'xref-lsp (lambda (_) (list (xref-make "h" (xref-make-file-location other 1 2))))
        (+test-editor--goto "Heading")
        (should-not (+my/at-declaration-p))))))

(ert-deftest editor/at-declaration-here-p-marker-in-another-buffer ()
  "A location on this line whose marker lands in another buffer: no."
  (+test-editor--visiting "decl/h.kt" (+test-editor--code)
    (+test-editor--goto "answer")
    (let* ((other (+test-buffer "elsewhere" "fun answer() = 42\n"))
           (item (xref-make "answer" (xref-make-file-location buffer-file-name 2 4))))
      (cl-letf (((symbol-function 'xref-location-marker)
                 (lambda (_) (with-current-buffer other (copy-marker 5)))))
        (should-not (+my/at-declaration--here-p (bounds-of-thing-at-point 'symbol)
                                                (list item)))))))

(ert-deftest editor/at-declaration-in-emacs-lisp ()
  "Emacs Lisp: Emacs itself knows where symbols are declared (its locations
carry no line: the line declaring them)."
  (let ((file (+test-file "decl/sample.el"
                          ";;; sample.el -*- lexical-binding: t; -*-\n(defun +test-editor-sample ()\n  1)\n\n(+test-editor-sample)\n")))
    (load file nil t)
    (+test-editor--visiting "decl/sample.el" (with-temp-buffer
                                               (insert-file-contents file)
                                               (buffer-string))
      (should (eq (xref-find-backend) 'elisp))
      (+test-editor--goto "+test-editor-sample")
      (should (+my/at-declaration-p))
      (+test-editor--goto "+test-editor-sample" 2)
      (should-not (+my/at-declaration-p)))))

(ert-deftest editor/at-declaration-keeps-point ()
  "Finding where Emacs Lisp declares a symbol moves point in its file: put
back (the usages are then listed for the symbol at point)."
  (let ((file (+test-file "decl/sample3.el"
                          ";;; sample3.el -*- lexical-binding: t; -*-\n(defun +test-editor-sample3 ()\n  1)\n\n(+test-editor-sample3)\n")))
    (load file nil t)
    (+test-editor--visiting "decl/sample3.el" (with-temp-buffer
                                                (insert-file-contents file)
                                                (buffer-string))
      (dolist (nth '(1 2))
        (+test-editor--goto "+test-editor-sample3" nth)
        (forward-char 3)
        (let ((point (point)))
          (+my/at-declaration-p)
          (should (= (point) point)))))))

(defmacro +test-editor--with-lookup (&rest body)
  "BODY with Doom's lookup commands recording into `called'."
  `(let ((called nil))
     (cl-letf (((symbol-function '+lookup/definition)
                (lambda (&rest _) (interactive) (push 'definition called)))
               ((symbol-function '+lookup/references)
                (lambda (&rest _) (interactive) (push 'references called))))
       ,@body)))

(ert-deftest editor/goto-declaration-or-usages ()
  "On a use: jump (gd); on the declaration: list usages (gD)."
  (+test-editor--visiting "decl/i.kt" (+test-editor--code)
    (+test-editor--with-backend '+test-editor (lambda (_) (list (+test-editor--here 2 4)))
      (+test-editor--with-lookup
       (+test-editor--goto "answer" 2)
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(definition)))
       (+test-editor--goto "answer")
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(references definition)))))))

(ert-deftest editor/goto-declaration-or-usages-no-symbol ()
  (+test-editor--visiting "decl/j.kt" "   \n"
    (+test-editor--with-lookup
     (should-error (call-interactively #'+my/goto-declaration-or-usages) :type 'user-error)
     (should-not called))))

(ert-deftest editor/goto-declaration-or-usages-emacs-lisp ()
  "In Emacs Lisp, on a defun's name: its usages."
  (let ((file (+test-file "decl/sample2.el"
                          ";;; -*- lexical-binding: t; -*-\n(defun +test-editor-sample2 () 1)\n(+test-editor-sample2)\n")))
    (load file nil t)
    (+test-editor--visiting "decl/sample2.el" (with-temp-buffer
                                                (insert-file-contents file)
                                                (buffer-string))
      (+test-editor--with-lookup
       (+test-editor--goto "+test-editor-sample2")
       (call-interactively #'+my/goto-declaration-or-usages)
       (+test-editor--goto "+test-editor-sample2" 2)
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(definition references)))))))

;; ====== TREE-SITTER ======

(defmacro +test-editor--counting-grammar-checks (&rest body)
  "BODY with `checks' counting the real `treesit-language-available-p' calls
(under the cache), the cache empty."
  `(let ((checks 0))
     (clrhash +my/treesit--available)
     (unwind-protect
         (+test-editor--with-advice 'treesit-language-available-p :around
             (lambda (fn &rest args) (cl-incf checks) (apply fn args))
           ,@body)
       (clrhash +my/treesit--available))))

(ert-deftest editor/treesit-answers-remembered ()
  (+test-editor--counting-grammar-checks
   (should-not (treesit-language-available-p '+test-editor-nolang))
   (should (= checks 1))
   (should-not (treesit-language-available-p '+test-editor-nolang))
   (should-not (treesit-language-available-p '+test-editor-nolang))
   (should (= checks 1))
   ;; Each language on its own.
   (treesit-language-available-p '+test-editor-other)
   (should (= checks 2))))

(ert-deftest editor/treesit-detail-from-the-cache ()
  "The full answer is cached: with DETAIL, the reason; without, yes / no."
  (+test-editor--counting-grammar-checks
   (should-not (treesit-language-available-p '+test-editor-nolang))
   (let ((detail (treesit-language-available-p '+test-editor-nolang t)))
     (should (consp detail))
     (should-not (car detail))
     (should (cdr detail)))                ; why it's missing
   (should (= checks 1))
   (should (consp (gethash '+test-editor-nolang +my/treesit--available)))))

(ert-deftest editor/treesit-available-grammar ()
  "An available grammar: t, (t . nil) with DETAIL, from the cache after."
  (+test-editor--counting-grammar-checks
   (+test-editor--with-advice 'treesit-language-available-p :override
       (lambda (language &optional detail)
         (if detail (cons (eq language 'fake) nil) (eq language 'fake)))
     (should (eq (treesit-language-available-p 'fake) t))
     (should (equal (treesit-language-available-p 'fake t) '(t)))
     (should (eq (treesit-language-available-p 'fake) t)))
   (should (<= checks 1))))

(ert-deftest editor/treesit-cache-cleared-on-install ()
  "Installing a grammar forgets the answers (it may be there now)."
  (+test-editor--counting-grammar-checks
   (treesit-language-available-p '+test-editor-nolang)
   (should (= (hash-table-count +my/treesit--available) 1))
   (+test-editor--with-advice 'treesit-install-language-grammar :override #'ignore
     (treesit-install-language-grammar '+test-editor-nolang))
   (should (= (hash-table-count +my/treesit--available) 0))
   (treesit-language-available-p '+test-editor-nolang)
   (should (= checks 2))))

;; ====== HIGHLIGHTING AFTER THE FIRST DISPLAY ======

(ert-deftest editor/defer-hook-first-on-find-file ()
  "On `find-file-hook' before saveplace (which measures the screen)."
  (require 'saveplace)
  (should (memq #'+my/defer-fontification-h find-file-hook))
  (should (= (alist-get #'+my/defer-fontification-h
                       (default-value (get 'find-file-hook 'hook--depth-alist)))
             -90))
  (let ((find-file-hook (default-value 'find-file-hook)))
    (add-hook 'find-file-hook #'save-place-find-file-hook t)
    (add-hook 'find-file-hook #'ignore)
    (should (< (seq-position find-file-hook #'+my/defer-fontification-h)
               (seq-position find-file-hook #'save-place-find-file-hook)))
    (should (< (seq-position find-file-hook #'+my/defer-fontification-h)
               (seq-position find-file-hook #'ignore)))))

(ert-deftest editor/defer-only-new-files-with-jit-lock ()
  ;; Highlighting on demand (jit-lock), not shown yet: wait for the display.
  (with-temp-buffer
    (setq-local jit-lock-mode t)
    (+my/defer-fontification-h)
    (should +my/defer-fontification)
    (should (memq #'+my/defer-fontification-shown-h pre-redisplay-functions))
    (should-not (memq #'+my/defer-fontification-shown-h
                      (default-value 'pre-redisplay-functions))))
  ;; No jit-lock: nothing to defer.
  (with-temp-buffer
    (setq-local jit-lock-mode nil)
    (+my/defer-fontification-h)
    (should-not +my/defer-fontification)
    (should-not (memq #'+my/defer-fontification-shown-h pre-redisplay-functions)))
  ;; Shown already (a file changed on disk, reverted): not deferred.
  (+test-with-reset
    (switch-to-buffer (+test-buffer "shown"))
    (setq-local jit-lock-mode t)
    (+my/defer-fontification-h)
    (should-not +my/defer-fontification)
    (should-not (memq #'+my/defer-fontification-shown-h pre-redisplay-functions))))

(ert-deftest editor/defer-on-opening-a-file ()
  "Opening a file (jit-lock on) defers its highlighting until it's shown."
  (let ((on (lambda () (setq-local jit-lock-mode t))))
    (add-hook 'find-file-hook on -95)
    (unwind-protect
        (+test-editor--visiting "defer/a.el" "(foo)\n"
          (should +my/defer-fontification)
          (should (memq #'+my/defer-fontification-shown-h pre-redisplay-functions)))
      (remove-hook 'find-file-hook on))))

(ert-deftest editor/defer-jit-lock-marks-and-waits ()
  "While deferred, jit-lock only marks the chunk as done, for now; the buffer
stays unmodified and nothing is highlighted."
  (with-temp-buffer
    (insert (make-string 2000 ?x))
    (set-buffer-modified-p nil)
    (setq-local jit-lock-mode t)
    (setq +my/defer-fontification t)
    (let ((ran 0)
          (jit-lock-chunk-size 100))
      (+test-editor--with-advice 'jit-lock-function :override (lambda (_) (cl-incf ran))
        (jit-lock-function 11))
      (should (= ran 0))
      (should-not (buffer-modified-p))
      (should-not (get-text-property 10 'fontified))
      (should (eq (get-text-property 11 'fontified) 'defer))
      (should (eq (get-text-property 110 'fontified) 'defer))
      (should-not (get-text-property 111 'fontified)))))

(ert-deftest editor/defer-jit-lock-stops-at-fontified-text ()
  (with-temp-buffer
    (insert (make-string 300 ?x))
    (put-text-property 50 300 'fontified t)
    (setq +my/defer-fontification t)
    (let ((jit-lock-chunk-size 500))
      (+test-editor--with-advice 'jit-lock-function :override #'ignore
        (jit-lock-function 1)))
    (should (eq (get-text-property 1 'fontified) 'defer))
    (should (eq (get-text-property 49 'fontified) 'defer))
    (should (eq (get-text-property 50 'fontified) t))))

(ert-deftest editor/defer-jit-lock-at-buffer-end ()
  (with-temp-buffer
    (insert "short")
    (setq +my/defer-fontification t)
    (+test-editor--with-advice 'jit-lock-function :override #'ignore
      (jit-lock-function 1))
    (should (eq (get-text-property 1 'fontified) 'defer))
    (should (eq (get-text-property 5 'fontified) 'defer))))

(ert-deftest editor/defer-jit-lock-normal-otherwise ()
  (with-temp-buffer
    (insert "text")
    (let ((ran nil))
      (+test-editor--with-advice 'jit-lock-function :override (lambda (start) (push start ran))
        (jit-lock-function 2))
      (should (equal ran '(2)))
      (should-not (get-text-property 2 'fontified)))))

(ert-deftest editor/defer-ends-right-after-the-first-display ()
  "A window draws it, plain: highlighted right after, on a timer (not an idle
one: opening a file can wait for input before anything was displayed)."
  (with-temp-buffer
    (insert "some code")
    (setq-local jit-lock-mode t)
    (+my/defer-fontification-h)
    (put-text-property (point-min) (point-max) 'fontified 'defer)
    (let ((scheduled nil)
          (refontified nil))
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (time repeat fn &rest args)
                   (push (list time repeat fn args) scheduled)))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (&rest _) (error "Not an idle timer"))))
        (run-hook-with-args 'pre-redisplay-functions (selected-window)))
      ;; Once: the hook is gone.
      (should-not (memq #'+my/defer-fontification-shown-h pre-redisplay-functions))
      (should (= (length scheduled) 1))
      (pcase-let ((`(,time ,repeat ,fn ,_) (car scheduled)))
        (should (eql time 0))
        (should-not repeat)
        (should +my/defer-fontification)                ; until the timer runs
        (cl-letf* ((real (symbol-function 'jit-lock-refontify))
                   ((symbol-function 'jit-lock-refontify)
                    (lambda (&rest args) (setq refontified t) (apply real args))))
          (funcall fn))
        (should-not +my/defer-fontification)
        (should refontified)
        (should-not (get-text-property 1 'fontified))))))

(ert-deftest editor/defer-timer-buffer-killed ()
  "The buffer killed before the timer ran: nothing done, no error."
  (let ((buffer (generate-new-buffer "defer-killed"))
        (scheduled nil))
    (with-current-buffer buffer
      (setq-local jit-lock-mode t)
      (+my/defer-fontification-h)
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _repeat fn &rest _) (setq scheduled fn))))
        (+my/defer-fontification-shown-h (selected-window))))
    (kill-buffer buffer)
    (cl-letf (((symbol-function 'jit-lock-refontify) (lambda (&rest _) (error "Not called"))))
      (funcall scheduled))))

(ert-deftest editor/defer-real-timer-runs ()
  "With the real timer: highlighted once timers run."
  (with-temp-buffer
    (insert "text")
    (setq-local jit-lock-mode t)
    (+my/defer-fontification-h)
    (put-text-property (point-min) (point-max) 'fontified 'defer)
    (+my/defer-fontification-shown-h (selected-window))
    (let ((end (+ (float-time) 2)))
      (while (and +my/defer-fontification (< (float-time) end))
        (accept-process-output nil 0.01)))
    (should-not +my/defer-fontification)
    (should-not (get-text-property 1 'fontified))))
