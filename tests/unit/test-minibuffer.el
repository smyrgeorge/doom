;;; tests/unit/test-minibuffer.el -*- lexical-binding: t; -*-
;; config/editor/minibuffer.el: a minibuffer left open (Emacs 31's
;; `minibuffer-nonselected' face) in the theme's colours, not Emacs's bright
;; yellow and dark red. Doom's theme colours stood in for (doom-themes isn't
;; loaded here).

(+test-load "config/editor")

;; ====== HELPERS ======

(defmacro +test-minibuffer-theme (bg yellow &rest body)
  "BODY with the theme's background BG and yellow YELLOW (`doom-color'), and
`doom-blend' giving \"blend YELLOW BG AMOUNT\"; the face's override spec put
back after."
  (declare (indent 2))
  `(let ((spec (get 'minibuffer-nonselected 'face-override-spec)))
     (unwind-protect
         (cl-letf (((symbol-function 'doom-color)
                    (lambda (name) (pcase name ('bg ,bg) ('yellow ,yellow))))
                   ((symbol-function 'doom-blend)
                    (lambda (colour bg amount) (format "blend %s %s %s" colour bg amount))))
           ,@body)
       (face-spec-set 'minibuffer-nonselected spec))))

(defun +test-minibuffer--spec ()
  "The face's override spec, as `+my/minibuffer-faces-h' set it."
  (get 'minibuffer-nonselected 'face-override-spec))

;; ====== TESTS ======

(ert-deftest minibuffer/emacs-31-marks-a-minibuffer-left-open ()
  "What this is about: Emacs 31's mode is on, its face there."
  (should (facep 'minibuffer-nonselected))
  (should (bound-and-true-p minibuffer-nonselected-mode)))

(ert-deftest minibuffer/left-open-in-the-theme-s-yellow ()
  "A dark theme: true colours, its yellow blended into its background by
`+my/minibuffer-nonselected-tint'; 256 colours, the palette's darkest yellow;
fewer, the region's. Never its own foreground or weight: the prompt and the
input keep theirs."
  (+test-minibuffer-theme "#282c34" "#ECBE7B"
    (+my/minibuffer-faces-h)
    (let ((spec (+test-minibuffer--spec)))
      (should (equal (plist-get (cdar spec) :background) "blend #ECBE7B #282c34 0.25"))
      (should (equal (caar spec) '((min-colors 257))))
      (should (equal (plist-get (cdadr spec) :background) "#5f5f00"))
      (should (equal (plist-get (cdr (nth 2 spec)) :inherit) 'region))
      ;; Emacs's own foreground and weight undone in each, its yellow too
      ;; where the region's colours stand in.
      (dolist (clause spec)
        (should (eq (plist-get (cdr clause) :foreground) 'unspecified))
        (should (eq (plist-get (cdr clause) :weight) 'unspecified)))
      (should (eq (plist-get (cdr (nth 2 spec)) :background) 'unspecified))
      ;; The face as it is (this frame has few colours: the region's).
      (should (eq (face-attribute 'minibuffer-nonselected :foreground) 'unspecified))
      (should (eq (face-attribute 'minibuffer-nonselected :weight) 'unspecified))
      (should-not (equal (face-attribute 'minibuffer-nonselected :background) "yellow")))))

(ert-deftest minibuffer/a-light-theme-s-lightest ()
  (+test-minibuffer-theme "#fafafa" "#986801"
    (+my/minibuffer-faces-h)
    (should (equal (plist-get (cdadr (+test-minibuffer--spec)) :background) "#ffffd7"))))

(ert-deftest minibuffer/the-tint-chosen-in-config-el ()
  (should (= (default-value '+my/minibuffer-nonselected-tint) 0.25))
  (+test-minibuffer-theme "#282c34" "#ECBE7B"
    (let ((+my/minibuffer-nonselected-tint 0.4))
      (+my/minibuffer-faces-h)
      (should (equal (plist-get (cdar (+test-minibuffer--spec)) :background)
                     "blend #ECBE7B #282c34 0.4")))))

(ert-deftest minibuffer/each-theme ()
  "Set again whenever a theme loads; Emacs's own face kept without Doom's
theme colours (or a theme without them: a name, not #rrggbb)."
  (should (memq #'+my/minibuffer-faces-h (default-value 'doom-load-theme-hook)))
  (let ((before (+test-minibuffer--spec)))
    (cl-letf (((symbol-function 'doom-color) nil)
              ((symbol-function 'doom-blend) nil))
      (+my/minibuffer-faces-h)
      (should (equal (+test-minibuffer--spec) before)))
    (+test-minibuffer-theme "unspecified-bg" "#ECBE7B"
      (+my/minibuffer-faces-h)
      (should (equal (+test-minibuffer--spec) before)))))
