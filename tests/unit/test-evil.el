;;; tests/unit/test-evil.el -*- lexical-binding: t; -*-
;; config/editor.el's Evil settings: saving returns to normal state; q closes transient menus
;; (unless a menu uses q itself).

(+test-load "config/editor")

;; Its q keys wait for transient (`after!'): not loaded yet here.
(defconst +test-evil--transient-loaded-first (featurep 'transient))
(require 'transient)

;; ====== HELPERS ======

(defvar +test-evil--ran nil "Suffixes the test menus ran, latest first.")

(defun +test-evil--other () (interactive) (push 'other +test-evil--ran))
(defun +test-evil--own-q () (interactive) (push 'own-q +test-evil--ran))

(transient-define-prefix +test-evil--menu ()
  "A menu without q."
  [("x" "Other" +test-evil--other)
   ("y a" "Two keys" +test-evil--other)])

(transient-define-prefix +test-evil--menu-with-q ()
  "A menu with its own q (like magit's dispatch)."
  [("q" "Own q" +test-evil--own-q)])

(transient-define-prefix +test-evil--parent ()
  "A menu opening another."
  [("s" "Sub-menu" +test-evil--menu)])

(defun +test-evil--menu-command ()
  "The menu open now (its command), or nil."
  (and transient--prefix (oref transient--prefix command)))

(defmacro +test-evil--transient (&rest body)
  "BODY with no menu open before or after; keys typed with `+test-evil--keys'."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+test-evil--ran nil))
       (unwind-protect (progn ,@body)
         (while transient--prefix
           (execute-kbd-macro (kbd "C-g")))))))

(defun +test-evil--keys (keys)
  "Type KEYS (`kbd' syntax), as the user would."
  (execute-kbd-macro (kbd keys)))

;; ====== SAVING ======

(ert-deftest evil/save-hook ()
  (should (memq 'evil-normal-state after-save-hook)))

(ert-deftest evil/saving-returns-to-normal-state ()
  (+test-with-reset
    (let ((file (+test-file "evil/a.txt" "text\n")))
      (find-file file)
      (evil-insert-state)
      (insert "more ")
      (save-buffer)
      (should (evil-normal-state-p))
      ;; From visual and replace states too.
      (evil-visual-char)
      (should (evil-visual-state-p))
      (insert "x")
      (save-buffer)
      (should (evil-normal-state-p))
      (evil-replace-state)
      (insert "y")
      (save-buffer)
      (should (evil-normal-state-p)))))

(ert-deftest evil/saving-another-buffer-returns-it-to-normal-state ()
  "E.g. save all: each saved buffer, not the current one."
  (+test-with-reset
    (let ((saved (find-file-noselect (+test-file "evil/b.txt" "text\n")))
          (current (find-file-noselect (+test-file "evil/c.txt" "text\n"))))
      (switch-to-buffer current)
      (evil-insert-state)
      (with-current-buffer saved
        (evil-insert-state)
        (insert "change")
        (save-buffer)
        (should (evil-normal-state-p)))
      (should (evil-insert-state-p)))))

(ert-deftest evil/not-saving-keeps-the-state ()
  (+test-with-reset
    (let ((file (+test-file "evil/d.txt" "text\n")))
      (find-file file)
      (evil-insert-state)
      (insert "x")
      (should (evil-insert-state-p)))))

;; ====== Q CLOSES TRANSIENT MENUS ======

(ert-deftest evil/q-keys-once-transient-loads ()
  (should-not +test-evil--transient-loaded-first)
  (should (eq (keymap-lookup transient-base-map "q") #'transient-quit-one))
  (should (eq (keymap-lookup transient-sticky-map "q") #'transient-quit-seq))
  ;; Every menu's map has the base one under it.
  (should (eq (keymap-parent transient-map) transient-base-map)))

(ert-deftest evil/q-closes-a-menu ()
  (+test-evil--transient
    (+test-evil--keys "M-x +test-evil--menu RET")
    (should (eq (+test-evil--menu-command) '+test-evil--menu))
    (+test-clear-messages)
    (+test-evil--keys "q")
    (should-not (+test-evil--menu-command))
    (should (= (+test-messages "Unbound suffix") 0))))

(ert-deftest evil/q-in-a-sub-menu-goes-back-one ()
  "Like Esc: one menu back."
  (+test-evil--transient
    (+test-evil--keys "M-x +test-evil--parent RET s")
    (should (eq (+test-evil--menu-command) '+test-evil--menu))
    (+test-evil--keys "q")
    (should (eq (+test-evil--menu-command) '+test-evil--parent))
    (+test-evil--keys "q")
    (should-not (+test-evil--menu-command))))

(ert-deftest evil/q-ends-a-key-sequence-started ()
  "Half a two-key suffix typed: q gives that up, the menu stays."
  (+test-evil--transient
    (+test-evil--keys "M-x +test-evil--menu RET y q")
    (should (eq (+test-evil--menu-command) '+test-evil--menu))
    (should-not +test-evil--ran)
    (+test-evil--keys "q")
    (should-not (+test-evil--menu-command))))

(ert-deftest evil/a-menu-with-its-own-q-keeps-it ()
  "magit's dispatch (bury), blame, git-timemachine: their q."
  (+test-evil--transient
    (+test-evil--keys "M-x +test-evil--menu-with-q RET q")
    (should (equal +test-evil--ran '(own-q)))))

(ert-deftest evil/other-keys-still-work ()
  (+test-evil--transient
    (+test-evil--keys "M-x +test-evil--menu RET x")
    (should (equal +test-evil--ran '(other)))
    (should-not (+test-evil--menu-command))))

(ert-deftest evil/without-it-q-was-unbound ()
  "What q did before: \"Unbound suffix\", the menu still open."
  (+test-evil--transient
    (unwind-protect
        (progn
          (keymap-unset transient-base-map "q" t)
          (+test-evil--keys "M-x +test-evil--menu RET")
          (+test-clear-messages)
          (+test-evil--keys "q")
          (should (eq (+test-evil--menu-command) '+test-evil--menu))
          (should (= (+test-messages "Unbound suffix: .q.") 1)))
      (keymap-set transient-base-map "q" #'transient-quit-one))))

;; ====== LOADED ======

(ert-deftest evil/config-el-loads-it ()
  "In config/editor.el, which config.el loads."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (should (member '(load! "config/editor") forms)))))
