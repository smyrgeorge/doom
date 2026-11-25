;;; tests/unit/test-modeline.el -*- lexical-binding: t; -*-
;; config/editor/modeline.el: a space after the mode line's last item on the right,
;; in every doom-modeline layout; each window's mode line its own layout (narrow
;; or not) and the path it has room for. As drawn, in pixels:
;; tests/e2e/test-modeline.el.

(+test-load "config/editor")

;; Done once doom-modeline loads (`after!'): not loaded yet here.
(defconst +test-modeline--loaded-first (featurep 'doom-modeline))
(require 'doom-modeline)

(defconst +test-modeline--layouts
  '(main minimal special project dashboard vcs package info media message pdf
    org-src helm git-timemachine calculator speedbar)
  "doom-modeline's layouts.")

(defun +test-modeline--rhs (name)
  (nth 2 (assq name doom-modeline--modelines)))

(defmacro +test-modeline--with-layouts (layouts &rest body)
  "BODY with LAYOUTS ((NAME LHS RHS)...) defined too, removed after."
  (declare (indent 1))
  `(let ((before (copy-tree doom-modeline--modelines)))
     (unwind-protect
         (progn
           (pcase-dolist (`(,name ,lhs ,rhs) ,layouts)
             (doom-modeline-def-modeline name lhs rhs))
           ,@body)
       (setq doom-modeline--modelines before))))

;; ====== A SPACE ON THE RIGHT ======

(ert-deftest modeline/space-once-doom-modeline-loads ()
  (should-not +test-modeline--loaded-first)
  (should (equal (car (last (+test-modeline--rhs 'main))) " ")))

(ert-deftest modeline/every-layout ()
  (dolist (name +test-modeline--layouts)
    (let ((rhs (+test-modeline--rhs name)))
      (should rhs)
      (should (equal (car (last rhs)) " "))))
  ;; Any others doom-modeline has too.
  (pcase-dolist (`(,name ,_ ,rhs) doom-modeline--modelines)
    (when rhs
      (should (equal (list name (car (last rhs))) (list name " "))))))

(ert-deftest modeline/one-space ()
  "Only one, and the items kept before it."
  (pcase-dolist (`(,name ,_ ,rhs) doom-modeline--modelines)
    (when rhs
      (should-not (equal (last rhs 2) '(" " " ")))
      (should (> (length rhs) 1))
      (ignore name))))

(ert-deftest modeline/the-mode-line-ends-with-it ()
  "The layout's format (what the mode line shows) has the space last."
  (with-temp-buffer
    (let ((format (doom-modeline-format--main)))
      (should (equal (car (last (car (last format)))) " ")))))

(ert-deftest modeline/again-adds-none ()
  "Applied again (the config reloaded): no second space."
  (let ((before (copy-tree doom-modeline--modelines)))
    (+test-load "config/editor/modeline")
    (should (equal doom-modeline--modelines before))))

(ert-deftest modeline/layouts-defined-before-it-runs ()
  "A layout with items on the right gets the space; one without, or with one
already, stays as it is."
  (+test-modeline--with-layouts '((+test-a (bar buffer-info) (major-mode))
                                  (+test-b (bar buffer-info) nil)
                                  (+test-c (bar buffer-info) (major-mode " ")))
    (+test-load "config/editor/modeline")
    (should (equal (+test-modeline--rhs '+test-a) '(major-mode " ")))
    (should (equal (+test-modeline--rhs '+test-b) nil))
    (should (equal (+test-modeline--rhs '+test-c) '(major-mode " ")))
    ;; The left side untouched.
    (should (equal (nth 1 (assq '+test-a doom-modeline--modelines)) '(bar buffer-info)))
    ;; Its format redefined with it.
    (should (equal (car (last (car (last (doom-modeline-format--+test-a))))) " "))))

;; ====== EACH WINDOW ITS OWN LAYOUT ======

(defconst +test-modeline--path "src/main/kotlin/com/example/agreements/AgreementController.kt"
  "A deep path in a project.")

(defmacro +test-modeline--deep (&rest body)
  "BODY in a buffer visiting `+test-modeline--path' in a project (\"app\"),
shown in the only window; doom-modeline's names as Doom has them
\(relative-from-project); the narrow layout in 20 columns or less (batch
Emacs's frame is 80)."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((root (file-truename (+test-tmp-file "modeline/app/")))
            (file (expand-file-name +test-modeline--path root))
            (doom-modeline-buffer-file-name-style 'relative-from-project)
            (doom-modeline-window-width-limit 20))
       (make-directory (file-name-directory file) t)
       (with-temp-file file (insert "class A\n"))
       (let ((buffer (find-file-noselect file)))
         (unwind-protect
             (progn
               (switch-to-buffer buffer)
               (setq-local doom-modeline--project-root root)
               (setq-local doom-modeline--buffer-file-name nil)
               (setq-local +my/modeline--names nil)
               ,@body)
           (kill-buffer buffer))))))

(defun +test-modeline--draw (window)
  "WINDOW's mode line drawn (its format worked out, WINDOW selected then, as
redisplay does)."
  (with-selected-window window
    (doom-modeline-format--main)))

(ert-deftest modeline/every-layout-fitted ()
  "Every layout's format works its window out (`+my/modeline-fit-a'), those
defined later too."
  (pcase-dolist (`(,name . ,_) doom-modeline--modelines)
    (should (advice-member-p #'+my/modeline-fit-a (intern (format "doom-modeline-format--%s" name)))))
  (+test-modeline--with-layouts '((+test-later (bar buffer-info) (major-mode)))
    (should (advice-member-p #'+my/modeline-fit-a 'doom-modeline-format--+test-later))))

(ert-deftest modeline/narrow-layout-per-window ()
  "The narrow layout worked out for the window whose mode line is drawn: a
narrow pane not selected gets it (doom-modeline worked it out from the
selected window's width); two windows on one buffer, each its own."
  (+test-modeline--deep
    (let* ((doom-modeline-window-width-limit 40)
           (wide (selected-window))
           (narrow (split-window wide -30 'left)))
      (should (eq (window-buffer narrow) (current-buffer)))
      (should (<= (window-total-width narrow) 40))
      (should (> (window-total-width wide) 40))
      ;; As doom-modeline has it: from the selected window's width.
      (doom-modeline-window-size-change)
      (should-not doom-modeline--limited-width-p)
      (+test-modeline--draw narrow)
      (should doom-modeline--limited-width-p)
      (+test-modeline--draw wide)
      (should-not doom-modeline--limited-width-p))))

(ert-deftest modeline/names-from-the-longest ()
  "The names the mode line can show: doom-modeline's (Doom's
relative-from-project), its folders cut to their first letter, the file's
name; worked out with doom-modeline's."
  (+test-modeline--deep
    (doom-modeline-update-buffer-file-name)
    (should (equal (mapcar #'substring-no-properties +my/modeline--names)
                   (list (concat "app/" +test-modeline--path)
                         "app/s/m/k/c/e/a/AgreementController.kt"
                         "AgreementController.kt")))
    (should (eq (car +my/modeline--names) doom-modeline--buffer-file-name)))
  ;; Shallow: no shorter one but the file's name.
  (with-temp-buffer
    (setq doom-modeline--buffer-file-name (propertize "app/a.kt" 'face 'bold))
    (setq buffer-file-name "/tmp/app/a.kt")
    (cl-letf (((symbol-function 'doom-modeline-buffer-file-name)
               (lambda () (if (eq doom-modeline-buffer-file-name-style 'file-name) "a.kt" "app/a.kt"))))
      (+my/modeline-names-a))
    (should (equal +my/modeline--names '("app/a.kt" "a.kt")))
    (setq buffer-file-name nil))
  ;; Not a file's: its name only.
  (with-temp-buffer
    (doom-modeline-update-buffer-file-name)
    (should (equal (mapcar #'substring-no-properties +my/modeline--names) (list (buffer-name))))))

(defmacro +test-modeline--widths (room rhs &rest body)
  "BODY with the mode line ROOM wide, its right side RHS wide, its left side
10 and the name shown (widths in columns: batch Emacs draws no mode line);
no choice kept from before."
  (declare (indent 2))
  `(cl-letf (((symbol-function '+my/modeline--room) (lambda () ,room))
             ((symbol-function '+my/modeline--string-width) #'string-width)
             ;; doom-modeline's, its right side's width.
             ((symbol-function 'doom-modeline-string-pixel-width) (lambda (_) ,rhs))
             ((symbol-function '+my/modeline--left)
              (lambda (_) (concat (make-string 10 ?<) doom-modeline--buffer-file-name)))
             ((symbol-function '+my/modeline--right) (lambda (_) (make-string ,rhs ?>))))
     (dolist (window (window-list))
       (set-window-parameter window '+my/modeline-fit nil))
     ,@body))

(ert-deftest modeline/the-path-the-window-has-room-for ()
  "In the wide layout, the longest name the window has room for with the
rest of the line (the position on the left, the right side): the path,
else its folders shortened, else the file's name."
  (+test-modeline--deep
    (let ((full (concat "app/" +test-modeline--path)))
      (dolist (case `((200 30 . ,full)
                      (,(+ 10 (length full) 30) 30 . ,full)
                      (,(+ 10 (length full) 29) 30 . "app/s/m/k/c/e/a/AgreementController.kt")
                      (100 30 . "app/s/m/k/c/e/a/AgreementController.kt")
                      (100 55 . "AgreementController.kt")
                      ;; Not even that: the file's name all the same.
                      (40 55 . "AgreementController.kt")))
        (pcase-let ((`(,room ,rhs . ,name) case))
          (+test-modeline--widths room rhs
            (+test-modeline--draw (selected-window))
            (should (equal (list room rhs (substring-no-properties doom-modeline--buffer-file-name))
                           (list room rhs name)))))))))

(ert-deftest modeline/the-path-per-window ()
  "Two windows on one buffer, each drawn with the name it has room for; the
buffer-info segment shows it."
  (+test-modeline--deep
    (let* ((left (selected-window))
           (right (split-window left nil 'right))
           (full (concat "app/" +test-modeline--path)))
      ;; The right one 200 wide, the left one 100.
      (+test-modeline--widths (if (eq (selected-window) right) 200 100) 30
        (+test-modeline--draw right)
        (should (equal (substring-no-properties doom-modeline--buffer-file-name) full))
        (should (string-search full (substring-no-properties
                                     (with-selected-window right (doom-modeline-segment--buffer-info)))))
        (+test-modeline--draw left)
        (should (equal (substring-no-properties doom-modeline--buffer-file-name)
                       "app/s/m/k/c/e/a/AgreementController.kt"))
        (should (string-search "app/s/m/k/c/e/a/AgreementController.kt"
                               (substring-no-properties
                                (with-selected-window left (doom-modeline-segment--buffer-info)))))))))

(ert-deftest modeline/the-choice-kept-while-the-line-is-the-same ()
  "Measured once for the window while its width and the line's text are the
same (the position's width too); again when one changes."
  (+test-modeline--deep
    (let ((rhs 30) (measured 0))
      (+test-modeline--widths 100 rhs
        (cl-letf* ((choose (symbol-function '+my/modeline--choose))
                   ((symbol-function '+my/modeline--choose)
                    (lambda (&rest args) (cl-incf measured) (apply choose args))))
          (+test-modeline--draw (selected-window))
          (+test-modeline--draw (selected-window))
          (should (= measured 1))
          (should (equal (substring-no-properties doom-modeline--buffer-file-name)
                         "app/s/m/k/c/e/a/AgreementController.kt"))
          ;; The right side changed (a check's count, a branch).
          (setq rhs 31)
          (+test-modeline--draw (selected-window))
          (should (= measured 2))
          ;; Another window, wider or narrower.
          (split-window nil nil 'right)
          (+test-modeline--draw (selected-window))
          (should (= measured 3)))))))

(ert-deftest modeline/worked-out-with-another-window-selected ()
  "Emacs works out a window's mode line as Lisp asks for its geometry, another
window selected (the treemacs pane): its format is doom-modeline's as it is,
nothing measured (the sides were formatted in the selected window's buffer)
or kept on the selected window. Drawn in its own window: fitted as before.
Formatted for real (batch Emacs formats no mode line):
tests/e2e/test-modeline.el."
  (+test-modeline--deep
    (let* ((file (current-buffer))
           (file-window (selected-window))
           (other (get-buffer-create "*test other*"))
           (window (split-window nil nil 'right))
           (measured nil))
      (set-window-buffer window other)
      (unwind-protect
          (cl-letf* ((left (symbol-function '+my/modeline--left))
                     ((symbol-function '+my/modeline--left)
                      (lambda (format) (push (buffer-name) measured) (funcall left format))))
            ;; As `pos-visible-in-window-p' on the file's window has it.
            (with-selected-window window
              (with-current-buffer file
                (let ((format (doom-modeline-format--main)))
                  (should (equal (car (last (car (last format)))) " "))))
              (should-not (window-parameter nil '+my/modeline-fit))
              (should-not (window-parameter nil '+my/modeline-narrower)))
            (should-not measured)
            ;; In its own window: fitted, measured there.
            (+test-modeline--draw file-window)
            (should (equal measured (list (buffer-name file)))))
        (kill-buffer other)))))

(ert-deftest modeline/the-narrow-layout-chooses-no-path ()
  "The narrow layout (the buffer's name only): no path chosen, the names
left as they were."
  (+test-modeline--deep
    (let ((doom-modeline-window-width-limit 1000)
          (chosen nil))
      (cl-letf (((symbol-function '+my/modeline--choose) (lambda (&rest _) (setq chosen t) "x")))
        (+test-modeline--draw (selected-window))
        (should doom-modeline--limited-width-p)
        (should-not chosen)))))

;; ====== NARROWER STILL ======

(defconst +test-modeline--narrow-left
  (concat "<<" (propertize "AgreementController.kt" 'help-echo "Buffer name\nmouse-1: Previous buffer")
          "  1:0 50%")
  "A narrow layout's left side as drawn: the buffer's name, the position.")

(defmacro +test-modeline--narrow (room &rest body)
  "BODY with the mode line ROOM wide (columns), the right side's segments
plain strings, no choice kept from before; MEASURED counts the measures."
  (declare (indent 1))
  `(let ((measured 0))
     (cl-letf (((symbol-function '+my/modeline--room) (lambda () (cl-incf measured) ,room))
               ((symbol-function '+my/modeline--string-width) #'string-width)
               ((symbol-function 'format-mode-line)
                (lambda (format &rest _) (apply #'concat (seq-filter #'stringp format)))))
       (set-window-parameter nil '+my/modeline-narrower nil)
       ,@body)))

(defun +test-modeline--narrow-format (display)
  "A narrow layout's format: its left side, the space (DISPLAY), its right
side's segments (10 columns)."
  (list '("left") (propertize " " 'display display) (list "check" "+ " "mode" " ")))

(ert-deftest modeline/narrower-room-for-it-all ()
  "Room for both sides: as it is, measured once while the line is the same."
  (+test-modeline--narrow 60
    (let ((format (+test-modeline--narrow-format '(space :align-to (- right (10))))))
      (should (eq (+my/modeline--narrower format +test-modeline--narrow-left) format))
      (should (eq (+my/modeline--narrower format +test-modeline--narrow-left) format))
      (should (= measured 1)))))

(ert-deftest modeline/narrower-the-right-side-goes-first ()
  "No room: the right side's segments dropped from its left (the last kept
longest), its space aligned to what's left (GUI's and a terminal's)."
  (+test-modeline--narrow 40
    (let ((result (+my/modeline--narrower (+test-modeline--narrow-format '(space :align-to (- right (10))))
                                          +test-modeline--narrow-left)))
      ;; The left side 33 wide, so 7 for the right: "+ ", "mode" and " ".
      (should (equal (car result) '("left")))
      (should (equal (nth 2 result) '("+ " "mode" " ")))
      (should (equal (get-text-property 0 'display (nth 1 result)) '(space :align-to (- right (7)))))))
  (+test-modeline--narrow 40
    (let ((result (+my/modeline--narrower (+test-modeline--narrow-format '(space :align-to (100)))
                                          +test-modeline--narrow-left)))
      (should (equal (get-text-property 0 'display (nth 1 result)) '(space :align-to (105)))))))

(ert-deftest modeline/narrower-the-name-cut ()
  "No room for the left side alone: the right side gone, the buffer's name
cut with …, the position kept; nothing past the window's edge."
  (+test-modeline--narrow 25
    (let* ((result (+my/modeline--narrower (+test-modeline--narrow-format '(space :align-to (- right (10))))
                                           +test-modeline--narrow-left))
           (line (car result)))
      (should (= (length result) 1))
      (should (stringp line))
      (should (equal (substring-no-properties line) "<<AgreementCont…  1:0 50%%"))
      ;; Its % escaped: shown as one.
      (should (<= (string-width (string-replace "%%" "%" line)) 25))
      ;; The name's properties kept (its clicks, its help).
      (should (string-prefix-p "Buffer name" (get-text-property 2 'help-echo line))))))

;; ====== LOADED ======

(defun +test-modeline--forms (file)
  "FILE's (of this config) top-level forms."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      forms)))

(ert-deftest modeline/config-el-loads-it ()
  "config.el loads the editor, which loads it."
  (should (member '(load! "config/editor") (+test-modeline--forms "config.el")))
  (should (member '(load! "editor/modeline") (+test-modeline--forms "config/editor.el"))))

;; ====== AGENT UI'S VIEWS ======

(ert-deftest modeline/an-agent-ui-canvas-s-layout ()
  "An Agent UI canvas's layout: the main one, what Agent UI's bar says
under its view (`agent-ui-pane-mode-line-text') in place of the major mode;
elsewhere (no view, a view saying nothing) the major mode."
  (should (equal (cdr (assq 'agent-ui-canvas-mode doom-modeline-mode-alist)) 'agent-ui))
  (should (equal (nth 1 (assq 'agent-ui doom-modeline--modelines)) (nth 1 (assq 'main doom-modeline--modelines))))
  (should (equal (+test-modeline--rhs 'agent-ui) (cl-substitute 'agent-ui 'major-mode (+test-modeline--rhs 'main))))
  (should (equal (car (last (+test-modeline--rhs 'agent-ui))) " "))
  (with-temp-buffer
    (setq mode-name "Agent UI")
    (let ((said (lambda (text)
                  (cl-letf (((symbol-function 'agent-ui-pane-mode-line-text) (lambda (&optional _) text))
                            ((symbol-function 'doom-modeline-segment--major-mode) (lambda () " Agent UI ")))
                    (string-trim (substring-no-properties (doom-modeline-segment--agent-ui)))))))
      (should (equal (funcall said '("Agent UI · 2 views")) "Agent UI · 2 views"))
      (should (equal (funcall said '(nil . "q close")) "q close"))
      (should (string-match-p "\\`Agent UI · 2 views +q close\\'" (funcall said '("Agent UI · 2 views" . "q close"))))
      (should (equal (funcall said nil) "Agent UI")))))
