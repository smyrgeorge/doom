;;; tests/e2e/test-modeline.el -*- lexical-binding: t; -*-
;; config/editor/modeline.el in a GUI Emacs: doom-modeline's mode line as
;; drawn, in pixels. A deep project path in a 100-column pane leaves the
;; position and the right side on the screen; a 60-column pane shows the
;; name, the position and the check; a narrow pane not selected gets the
;; narrow layout.

(+test-load "config/window" "config/editor")
(require 'doom-modeline)
(require 'flymake)

;; As Doom has doom-modeline (modules/ui/modeline).
(setq doom-modeline-bar-width 3
      doom-modeline-minor-modes nil
      doom-modeline-major-mode-icon nil
      doom-modeline-check 'simple
      doom-modeline-buffer-file-name-style 'relative-from-project
      doom-modeline-buffer-encoding 'nondefault)
(doom-modeline-mode 1)
(column-number-mode 1)

;; As Doom: no scroll bars, a divider of a pixel between windows.
(scroll-bar-mode -1)
(setq window-divider-default-places t
      window-divider-default-right-width 1
      window-divider-default-bottom-width 1)
(window-divider-mode 1)

(defconst +test-modeline--path
  "src/main/kotlin/com/example/agreements/renewals/AgreementController.kt"
  "A deep path in a project (\"app\").")

;; ====== HELPERS ======

(defun +test-modeline--visit (name)
  "A file NAME (under the project \"app\", made) visited, flymake on (the
check shown), doom-modeline's project root set; its buffer."
  (let* ((root (file-truename (+test-tmp-file "modeline/app/")))
         (file (expand-file-name name root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "class AgreementController\n"))
    (with-current-buffer (find-file-noselect file)
      (setq-local doom-modeline--project-root root)
      ;; Its names again, in the project.
      (doom-modeline-update-buffer-file-name)
      (flymake-mode 1)
      (current-buffer))))

(defun +test-modeline--drawn ()
  "The windows' mode lines drawn, again."
  (force-mode-line-update t)
  (redisplay t)
  (+test-sleep 0.1))

(defun +test-modeline--sides (window)
  "WINDOW's mode line as drawn: (LEFT RIGHT ROOM), its left and right sides'
text and the width of both and of the mode line, in pixels."
  (with-selected-window window
    (let* ((format (doom-modeline-format--main))
           (left (format-mode-line (car format)))
           (right (format-mode-line (nth 2 format))))
      (list left right (+my/modeline--string-width left) (+my/modeline--string-width right)
            (+my/modeline--room)))))

(defun +test-modeline--fits-p (window)
  "Non-nil if WINDOW's mode line has room for both its sides."
  (pcase-let ((`(,_ ,_ ,left ,right ,room) (+test-modeline--sides window)))
    (<= (+ left right) room)))

;; ====== TESTS ======

(ert-deftest e2e-modeline/a-deep-path-in-100-columns ()
  "A deep path in a 100-column pane: shortened, the position and the right
side (the check last) on the screen; in a wider frame, the whole path."
  (+test-with-reset
    (+test-e2e-frame-reset)
    (let ((buffer (+test-modeline--visit +test-modeline--path))
          (window (selected-window)))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (set-window-buffer (split-window window 100 'right) (+test-buffer "other"))
      (should (= (window-total-width window) 100))
      (+test-modeline--drawn)
      (with-current-buffer buffer
        (should-not doom-modeline--limited-width-p)
        (should (string-suffix-p "AgreementController.kt" doom-modeline--buffer-file-name))
        (should (< (length doom-modeline--buffer-file-name) (length (car +my/modeline--names)))))
      (should (+test-modeline--fits-p window))
      (pcase-let ((`(,left ,right . ,_) (+test-modeline--sides window)))
        (should (string-search "1:0" left))
        (should (string-search "AgreementController.kt" left))
        ;; flymake's, last but the space.
        (should (string-search (substring-no-properties (format-mode-line (doom-modeline-segment--check)))
                               right)))
      ;; Room for it all: the whole path.
      (delete-other-windows)
      (+test-modeline--drawn)
      (with-current-buffer buffer
        (should (equal doom-modeline--buffer-file-name (car +my/modeline--names)))
        (should (string-search +test-modeline--path doom-modeline--buffer-file-name)))
      (should (+test-modeline--fits-p window)))))

(ert-deftest e2e-modeline/sixty-columns-name-position-check ()
  "A 60-column pane: the narrow layout, its name, position and check shown."
  (+test-with-reset
    (+test-e2e-frame-reset)
    (let ((buffer (+test-modeline--visit +test-modeline--path))
          (window (selected-window)))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (set-window-buffer (split-window window 60 'right) (+test-buffer "other"))
      (+test-modeline--drawn)
      (with-current-buffer buffer
        (should doom-modeline--limited-width-p))
      (should (+test-modeline--fits-p window))
      (pcase-let ((`(,left ,right . ,_) (+test-modeline--sides window)))
        (should (string-search "AgreementController.kt" left))
        (should (string-search "1:0" left))
        (should (string-search (substring-no-properties
                                (with-selected-window window
                                  (format-mode-line (doom-modeline-segment--check))))
                               right))))))

(ert-deftest e2e-modeline/a-narrow-pane-not-selected ()
  "A narrow pane not selected, beside a wide one: the narrow layout (it got
the wide one, worked out from the selected window)."
  (+test-with-reset
    (+test-e2e-frame-reset)
    (let ((wide (+test-modeline--visit +test-modeline--path))
          (narrow (+test-modeline--visit "src/main/kotlin/com/example/agreements/Agreement.kt"))
          (window (selected-window)))
      (switch-to-buffer wide)
      (delete-other-windows)
      (set-window-buffer (split-window window 110 'right) narrow)
      (should (eq (window-buffer (selected-window)) wide))
      (+test-modeline--drawn)
      (with-current-buffer narrow
        (should doom-modeline--limited-width-p))
      (with-current-buffer wide
        (should-not doom-modeline--limited-width-p)))))

;;; test-modeline.el ends here
