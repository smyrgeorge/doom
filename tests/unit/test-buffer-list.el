;;; tests/unit/test-buffer-list.el -*- lexical-binding: t; -*-
;; config/editor/buffer-list.el: the buffer list (SPC b i, ibuffer) grouped by
;; workspace. Real persp-mode (Doom's workspaces), nothing saved; without
;; workspaces, ibuffer-projectile's groups (stood in for).

(+test-load "config/editor")
(require 'ibuffer)
(require 'ibuf-ext)
(require 'persp-mode)

;; ====== HELPERS ======

(defmacro +test-bl (&rest body)
  "BODY with persp-mode on, its workspaces A and B (A current); persp-mode off,
the buffers made killed after."
  (declare (indent 0))
  `(+test-with-reset
     (let ((before (buffer-list))
           (persp-auto-save-opt 0)
           (persp-auto-resume-time -1)
           (persp-save-dir (file-name-as-directory (+test-tmp-file "persp"))))
       (persp-mode 1)
       (persp-add-new "A")
       (persp-add-new "B")
       (persp-frame-switch "A")
       (unwind-protect (progn ,@body)
         (persp-mode -1)
         (let ((kill-buffer-query-functions nil))
           (dolist (buffer (buffer-list))
             (unless (memq buffer before) (kill-buffer buffer))))))))

(defun +test-bl--in (buffer &rest workspaces)
  "BUFFER added to WORKSPACES (names)."
  (dolist (name workspaces)
    (persp-add-buffer buffer (persp-get-by-name name) nil nil))
  buffer)

(defun +test-bl--groups ()
  "SPC b i's list, opened: ((GROUP BUFFER-NAME...)...), as drawn."
  (ibuffer)
  (with-current-buffer "*Ibuffer*"
    (let (groups)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((group (get-text-property (point) 'ibuffer-filter-group-name))
              (buffer (get-text-property (point) 'ibuffer-properties)))
          (cond (group (push (list group) groups))
                ((and buffer groups) (push (buffer-name (car buffer)) (cdar groups)))))
        (forward-line 1))
      (mapcar (lambda (group) (cons (car group) (nreverse (cdr group))))
              (nreverse groups)))))

(defun +test-bl--group-of (name groups)
  "The group of GROUPS the buffer NAME is in."
  (car (seq-find (lambda (group) (member name (cdr group))) groups)))

;; ====== TESTS ======

(ert-deftest buffer-list/wired ()
  (should (memq #'+my/buffer-list-group-h ibuffer-hook))
  (should-not (memq 'ibuffer-projectile-set-filter-groups ibuffer-hook)))

(ert-deftest buffer-list/grouped-by-workspace ()
  "A group per workspace, in their order: a file, Beads' list, a Claude session
under the one they're in (the first, if several); a buffer in none under
Default (*Messages* there: ibuffer's own)."
  (+test-bl
    (let ((file (+test-bl--in (find-file-noselect (+test-file "a.txt" "a\n")) "A"))
          (issues (+test-bl--in (+test-buffer "*Beads: proj*" "issues\n") "A"))
          (session (+test-bl--in (+test-buffer "Claude Agent @ proj" "hi\n") "B"))
          (both (+test-bl--in (+test-buffer "notes" "x\n") "A" "B"))
          (none (+test-buffer "*no workspace*" "x\n")))
      (ignore file issues session both none)
      (let ((groups (+test-bl--groups)))
        (should (equal (seq-take (mapcar #'car groups) 2) '("A" "B")))
        (should (equal (+test-bl--group-of "a.txt" groups) "A"))
        (should (equal (+test-bl--group-of "*Beads: proj*" groups) "A"))
        (should (equal (+test-bl--group-of "Claude Agent @ proj" groups) "B"))
        (should (equal (+test-bl--group-of "notes" groups) "A"))
        (should (equal (+test-bl--group-of "*no workspace*" groups) "Default"))))))

(ert-deftest buffer-list/a-workspace-with-nothing-shown-has-no-group ()
  "A workspace none of whose buffers are listed: no group (ibuffer's empty
groups hidden, as Doom sets it)."
  (+test-bl
    (let ((ibuffer-show-empty-filter-groups nil))
      (+test-bl--in (+test-buffer "only in A" "x\n") "A")
      (should-not (assoc "B" (+test-bl--groups))))))

(ert-deftest buffer-list/without-workspaces-by-project ()
  "persp-mode off: ibuffer-projectile's groups, as Doom has them."
  (+test-with-reset
    (let ((persp-mode nil)
          (called 0))
      (cl-letf (((symbol-function 'ibuffer-projectile-set-filter-groups)
                 (lambda () (setq called (1+ called)))))
        (ibuffer)
        (should (= called 1)))
      (kill-buffer "*Ibuffer*"))))
