;;; tests/e2e/test-tabs-workspaces.el -*- lexical-binding: t; -*-
;; config/editor/tabs.el with persp-mode's workspaces, as Doom has them, in a
;; GUI Emacs: a window's tabs keep their order through a workspace switched
;; away from and back, and through workspaces saved to a file (readable) and
;; loaded again (doom-djc.14).

(+test-load "config/emacs" "config/editor")
(require 'tab-line)
(global-tab-line-mode 1)
;; As Doom: workspaces persp-mode's, their windows kept with its default
;; functions (`window-state-get' WRITABLE, `window-state-put').
(require 'persp-mode)
(setq persp-auto-resume-time -1
      persp-auto-save-opt 0
      persp-save-dir (+test-tmp-file "persp/"))
(persp-mode 1)

;; ====== HELPERS ======

(defun +test-tabw--files (&rest names)
  "Files NAMES (in a new folder) visited: their buffers, their tab line on."
  (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "tabw-") t))))
    (mapcar (lambda (name)
              (with-temp-file (expand-file-name name dir) (insert name "\n"))
              (with-current-buffer (find-file-noselect (expand-file-name name dir))
                (tab-line-mode 1)
                (current-buffer)))
            names)))

(defun +test-tabw--show (&rest buffers)
  "BUFFERS shown in the selected window one after the other, the frame
drawn after each."
  (dolist (buffer buffers)
    (switch-to-buffer buffer)
    (redisplay t)))

(defun +test-tabw--tabs ()
  "The selected window's tabs, as its tab line has them."
  (redisplay t)
  (+my/tabs-window-buffers))

(defmacro +test-tabw (&rest body)
  "BODY in a frame of its own windows, the workspaces it made killed after
\(their buffers kept), the frame back in the nil workspace."
  (declare (indent 0))
  `(let ((persps (persp-names)))
     (+test-e2e-frame-reset)
     (delete-other-windows)
     (unwind-protect (progn ,@body)
       (persp-frame-switch persp-nil-name)
       (dolist (name (persp-names))
         (unless (member name persps) (persp-kill name t)))
       (delete-other-windows))))

;; ====== TESTS ======

(ert-deftest e2e-tabs-workspaces/the-order-kept-through-a-switch ()
  "A B C D E, C shown with Cmd+3: another workspace and back, A B C D E, C
current (it went last before). Saved to a file, the file read back as text
\(no buffer object in it), loaded again and switched to: the same."
  (+test-tabw
    (persp-add-new "ws-tabs")
    (persp-frame-switch "ws-tabs")
    (let ((tabs (+test-tabw--files "a.txt" "b.txt" "c.txt" "d.txt" "e.txt")))
      (apply #'+test-tabw--show tabs)
      (+my/tabs-select-3)
      (should (equal (+test-tabw--tabs) tabs))
      ;; Another workspace and back.
      (persp-add-new "ws-other")
      (persp-frame-switch "ws-other")
      (+test-tabw--show (get-buffer-create "*elsewhere*"))
      (persp-frame-switch "ws-tabs")
      (should (eq (window-buffer) (nth 2 tabs)))
      (should (equal (+test-tabw--tabs) tabs))
      ;; Saved and loaded again.
      (let ((file (+test-tmp-file "persp/tabs")))
        (persp-save-state-to-file file)
        (with-temp-buffer
          (insert-file-contents file)
          (should-not (search-forward "#<" nil t))
          (goto-char (point-min))
          (should (search-forward "+my/tabs-order" nil t))
          ;; Every form read back.
          (goto-char (point-min))
          (should (eq (condition-case nil (while t (read (current-buffer))) (end-of-file 'read))
                      'read)))
        (persp-frame-switch "ws-other")
        (persp-load-state-from-file file)
        (persp-frame-switch "ws-tabs")
        (should (eq (window-buffer) (nth 2 tabs)))
        (should (equal (+test-tabw--tabs) tabs))))))

(ert-deftest e2e-tabs-workspaces/each-pane-its-own-order ()
  "Two panes, each its tabs in its own order: another workspace and back,
each pane's as it was."
  (+test-tabw
    (persp-add-new "ws-panes")
    (persp-frame-switch "ws-panes")
    (pcase-let ((`(,a ,b ,c ,x ,y ,z) (+test-tabw--files "a.txt" "b.txt" "c.txt" "x.txt" "y.txt" "z.txt")))
      (+test-tabw--show a b c a)
      (let ((right (split-window nil nil 'right)))
        ;; Its only tab x (a split shows the other pane's buffer first).
        (set-window-buffer right x)
        (set-window-prev-buffers right nil)
        (set-window-parameter right 'tab-line-buffers nil)
        (with-selected-window right
          (+test-tabw--show x y z x)))
      (should (equal (+test-tabw--tabs) (list a b c)))
      (persp-add-new "ws-other")
      (persp-frame-switch "ws-other")
      (+test-tabw--show (get-buffer-create "*elsewhere*"))
      (persp-frame-switch "ws-panes")
      (let* ((left (frame-first-window))
             (right (window-in-direction 'right left)))
        (should (eq (window-buffer left) a))
        (should (equal (with-selected-window left (+test-tabw--tabs)) (list a b c)))
        (should (eq (window-buffer right) x))
        (should (equal (with-selected-window right (+test-tabw--tabs)) (list x y z)))))))
