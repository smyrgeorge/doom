;;; tests/unit/test-terminal.el -*- lexical-binding: t; -*-
;; config/terminal.el: terminal (tty) frames: the terminal's background painted
;; with the theme's (OSC 11) and given back (OSC 111) on exit or when an
;; emacsclient -t frame closes; no menu bar; no tty-tip-mode.

;; As Doom has it, before this config.
(add-hook 'tty-setup-hook #'tty-tip-mode)

(+test-load "config/terminal")

;; The batch Emacs's frame is a terminal one, its terminal the test's output:
;; no escape codes there when it exits.
(add-hook 'kill-emacs-hook (lambda () (fset '+my/tty-reset-bg-h #'ignore)) -90)

;; ====== HELPERS ======

(defvar +test-terminal--sent nil "(STRING TERMINAL) sent, latest first.")

(defmacro +test-terminal (&rest body)
  "BODY with what is sent to terminals recorded in `+test-terminal--sent'."
  (declare (indent 0))
  `(let ((+test-terminal--sent nil))
     (cl-letf (((symbol-function 'send-string-to-terminal)
                (lambda (string &optional terminal)
                  (push (list string terminal) +test-terminal--sent))))
       ,@body)))

(defmacro +test-terminal--frames (frames &rest body)
  "BODY with FRAMES ((FRAME TYPE BACKGROUND [TERMINAL])...) the frames: TYPE
what `framep' says (t: a terminal's, ns: GUI), BACKGROUND its default face's,
TERMINAL its terminal (default: FRAME-terminal)."
  (declare (indent 1))
  `(let ((frames ,frames)
         (framep (symbol-function 'framep))
         (face-background (symbol-function 'face-background))
         (frame-terminal (symbol-function 'frame-terminal)))
     (cl-letf (((symbol-function 'frame-list) (lambda () (mapcar #'car frames)))
               ((symbol-function 'framep)
                (lambda (frame) (if (assq frame frames) (nth 1 (assq frame frames))
                                  (funcall framep frame))))
               ((symbol-function 'face-background)
                (lambda (face &optional frame &rest args)
                  (if (and (eq face 'default) (assq frame frames))
                      (nth 2 (assq frame frames))
                    (apply face-background face frame args))))
               ((symbol-function 'frame-terminal)
                (lambda (&optional frame)
                  (if (and frame (symbolp frame))
                      (or (nth 3 (assq frame frames)) (intern (format "%s-terminal" frame)))
                    (funcall frame-terminal frame)))))
       ,@body)))

;; ====== HOOKS ======

(ert-deftest terminal/hooks ()
  (should (memq '+my/tty-sync-bg-h doom-load-theme-hook))
  (should (memq '+my/tty-sync-bg-h tty-setup-hook))
  (should (memq '+my/tty-sync-bg-h after-make-frame-functions))
  (should (memq '+my/tty-reset-bg-h kill-emacs-hook))
  (should (memq '+my/tty-reset-frame-bg-h delete-frame-functions))
  (should (memq '+my/tty-no-menu-bar-h after-make-frame-functions))
  (should (memq '+my/tty-no-menu-bar-h tty-setup-hook)))

(ert-deftest terminal/no-tty-tip-mode ()
  "Doom's `tty-tip-mode' on terminal frames is off: it's global, GUI frames
drew their tips the terminal's way."
  (should-not (memq 'tty-tip-mode tty-setup-hook))
  ;; Loading again: still off, the hooks there once.
  (add-hook 'tty-setup-hook #'tty-tip-mode)
  (+test-load "config/terminal")
  (should-not (memq 'tty-tip-mode tty-setup-hook))
  (should (= (cl-count '+my/tty-sync-bg-h tty-setup-hook) 1)))

;; ====== THE TERMINAL'S BACKGROUND ======

(ert-deftest terminal/background-painted ()
  "OSC 11 with the theme's background, to the terminal of each terminal frame."
  (+test-terminal
    (+test-terminal--frames '((tty1 t "#282c34") (tty2 t "#1e1e1e"))
      (+my/tty-sync-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]11;#282c34\a" tty1-terminal)
                       ("\e]11;#1e1e1e\a" tty2-terminal)))))))

(ert-deftest terminal/background-of-the-real-frame ()
  "Batch Emacs's own frame is a terminal one."
  (should (eq (framep (selected-frame)) t))
  (let ((before (face-background 'default (selected-frame))))
    (unwind-protect
        (+test-terminal
          (set-face-background 'default "#112233" (selected-frame))
          (+my/tty-sync-bg-h)
          (should (equal +test-terminal--sent
                         (list (list "\e]11;#112233\a" (frame-terminal (selected-frame)))))))
      (set-face-background 'default before (selected-frame)))))

(ert-deftest terminal/background-not-for-gui-frames ()
  (+test-terminal
    (+test-terminal--frames '((gui ns "#282c34") (x x "#282c34") (tty t "#000000"))
      (+my/tty-sync-bg-h)
      (should (equal +test-terminal--sent '(("\e]11;#000000\a" tty-terminal)))))))

(ert-deftest terminal/background-only-a-colour-code ()
  "Not a #RRGGBB colour (no theme yet, a named colour): left alone."
  (+test-terminal
    (+test-terminal--frames '((a t "unspecified-bg") (b t "black") (c t nil))
      (+my/tty-sync-bg-h)
      (should-not +test-terminal--sent))))

(ert-deftest terminal/background-hook-arguments ()
  "Called with a frame (after-make-frame-functions) or none (themes)."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34"))
      (+my/tty-sync-bg-h 'tty)
      (+my/tty-sync-bg-h)
      (+my/tty-sync-bg-h 'tty 'more)
      (should (= (length +test-terminal--sent) 3)))))

(ert-deftest terminal/background-given-back-on-exit ()
  (+test-terminal
    (+test-terminal--frames '((tty1 t "#282c34") (gui ns "#282c34") (tty2 t "#282c34"))
      (+my/tty-reset-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]111\a" tty1-terminal) ("\e]111\a" tty2-terminal)))))))

(ert-deftest terminal/background-given-back-when-a-frame-closes ()
  "emacsclient -t: its frame closing gives its terminal its colour back."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34") (gui ns "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (frame) (memq frame '(tty gui)))))
        (+my/tty-reset-frame-bg-h 'tty)
        (should (equal +test-terminal--sent '(("\e]111\a" tty-terminal))))
        ;; GUI frames: nothing.
        (setq +test-terminal--sent nil)
        (+my/tty-reset-frame-bg-h 'gui)
        (should-not +test-terminal--sent)
        ;; The terminal gone already (its window closed): the frame is dead.
        (+my/tty-reset-frame-bg-h 'dead)
        (should-not +test-terminal--sent)))))

(ert-deftest terminal/background-kept-while-another-frame-shows-it ()
  "C-x 5 0 of one of two frames in a terminal: the other still shows the
theme's background; the last one gives it back."
  (+test-terminal
    (+test-terminal--frames '((one t "#282c34" shared) (two t "#282c34" shared)
                              (elsewhere t "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t)))
        (+my/tty-reset-frame-bg-h 'one)
        (should-not +test-terminal--sent)))
    (+test-terminal--frames '((two t "#282c34" shared) (elsewhere t "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t)))
        (+my/tty-reset-frame-bg-h 'two)
        (should (equal +test-terminal--sent '(("\e]111\a" shared))))))))

(ert-deftest terminal/background-closing-frame-errors-ignored ()
  (+test-terminal--frames '((tty t "#282c34"))
    (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t))
              ((symbol-function 'send-string-to-terminal)
               (lambda (&rest _) (error "Terminal gone"))))
      (should-not (+my/tty-reset-frame-bg-h 'tty)))))

;; ====== NO MENU BAR ======

(ert-deftest terminal/no-menu-bar-in-terminal-frames ()
  (let ((before (frame-parameter nil 'menu-bar-lines)))
    (unwind-protect
        (progn
          (set-frame-parameter nil 'menu-bar-lines 1)
          (+my/tty-no-menu-bar-h (selected-frame))
          (should (eql (frame-parameter nil 'menu-bar-lines) 0))
          ;; No frame: the selected one (emacs -nw's first).
          (set-frame-parameter nil 'menu-bar-lines 1)
          (+my/tty-no-menu-bar-h)
          (should (eql (frame-parameter nil 'menu-bar-lines) 0))
          ;; A new frame.
          (set-frame-parameter nil 'menu-bar-lines 1)
          (let ((after-make-frame-functions '(+my/tty-no-menu-bar-h)))
            (run-hook-with-args 'after-make-frame-functions (selected-frame)))
          (should (eql (frame-parameter nil 'menu-bar-lines) 0)))
      (set-frame-parameter nil 'menu-bar-lines before))))

(ert-deftest terminal/menu-bar-off-already-left-alone ()
  (let ((set nil))
    (cl-letf (((symbol-function 'frame-parameter) (lambda (_ p) (and (eq p 'menu-bar-lines) 0)))
              ((symbol-function 'set-frame-parameter) (lambda (&rest args) (setq set args))))
      (+my/tty-no-menu-bar-h (selected-frame)))
    (should-not set)))

(ert-deftest terminal/menu-bar-kept-in-gui-frames ()
  "macOS GUI frames: it lives in the system's menu bar."
  (let ((set nil))
    (+test-terminal--frames '((gui ns "#282c34"))
      (cl-letf (((symbol-function 'frame-parameter) (lambda (_ p) (and (eq p 'menu-bar-lines) 1)))
                ((symbol-function 'set-frame-parameter) (lambda (&rest args) (setq set args))))
        (+my/tty-no-menu-bar-h 'gui)))
    (should-not set)))

;; ====== LOADED ======

(ert-deftest terminal/config-el-loads-it ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (should (member '(load! "config/terminal") forms)))))
