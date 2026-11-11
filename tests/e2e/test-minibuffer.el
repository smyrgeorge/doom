;;; tests/e2e/test-minibuffer.el -*- lexical-binding: t; -*-
;; config/editor/minibuffer.el in a GUI Emacs: a minibuffer left open while
;; another window is selected, Emacs 31 covering it with the face
;; `minibuffer-nonselected', in the theme's tint (a true-colour frame's), not
;; bold dark red on yellow. Doom's theme colours stood in for.

(+test-load "config/editor")

(ert-deftest e2e-minibuffer/left-open-in-the-theme-s-tint ()
  "A prompt open, another window selected: its contents under the face, which
in this frame is the theme's tint, its prompt's and input's own colours and
weight; back in the minibuffer, gone."
  (let ((spec (get 'minibuffer-nonselected 'face-override-spec))
        seen)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'doom-color)
                     (lambda (name) (pcase name ('bg "#282c34") ('yellow "#ECBE7B"))))
                    ((symbol-function 'doom-blend) (lambda (&rest _) "#595046")))
            (+my/minibuffer-faces-h))
          (should (equal (face-attribute 'minibuffer-nonselected :background) "#595046"))
          (should (eq (face-attribute 'minibuffer-nonselected :foreground) 'unspecified))
          (should (eq (face-attribute 'minibuffer-nonselected :weight) 'unspecified))
          (delete-other-windows)
          (let ((other (split-window-right))
                (marked (lambda (buffer)
                          (with-current-buffer buffer
                            (seq-some (lambda (overlay)
                                        (eq (overlay-get overlay 'face) 'minibuffer-nonselected))
                                      (overlays-in (point-min) (point-max)))))))
            (run-at-time
             0.2 nil
             (lambda ()
               (unwind-protect
                   (let ((minibuffer (window-buffer (active-minibuffer-window))))
                     (select-window other)
                     (redisplay t)
                     (push (list :elsewhere (and (funcall marked minibuffer) t)) seen)
                     (select-window (active-minibuffer-window))
                     (redisplay t)
                     (push (list :back (and (funcall marked minibuffer) t)) seen))
                 (exit-minibuffer))))
            (read-from-minibuffer "Prompt: " "input")))
      (face-spec-set 'minibuffer-nonselected spec)
      (delete-other-windows))
    (should (equal (reverse seen) '((:elsewhere t) (:back nil))))))
