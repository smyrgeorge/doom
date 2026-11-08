;;; tests/unit/test-keys.el -*- lexical-binding: t; -*-
;; This config's keys on macOS and on Linux (config/os.el, KEYS): the Cmd
;; keys everywhere; Linux's Ctrl keys on Linux only, macOS's keys as they
;; were. The files binding them are loaded as on macOS (what they bound
;; then kept), then again as on Linux. Drawings' keys: test-excalidraw.el;
;; the sidebar's: test-treemacs.el.

(require 'xwidget)
(require 'json)
(require 'markdown-mode)
(require 'lsp-mode)
(require 'image-mode)

(defconst +test-keys--files
  '("config/window" "config/childframe" "config/banner" "config/editor" "config/search"
    "config/webkit" "config/markdown" "config/pdf" "config/image" "config/merge")
  "The files binding the keys below, in config.el's order.")

;; ====== THE KEYS ======

(defconst +test-keys--everywhere
  '((global-map nil "s-1" +my/tabs-select-1)
    (global-map nil "s-9" +my/tabs-select-9)
    (evil-normal-state-map nil "s-1" +my/tabs-select-1)
    (global-map nil "s-w" +my/tabs-close-current)
    (global-map nil "s-b" +my/goto-declaration-or-usages)
    (global-map nil "s-[" better-jumper-jump-backward)
    (global-map nil "s-]" better-jumper-jump-forward)
    (global-map nil "s-F" +default/search-project)
    (global-map nil "M-RET" nil)
    (evil-normal-state-map nil "M-RET" +my/context-actions)
    (+my/image-mode-map nil "s-=" +my/image-zoom-in)
    (+my/image-mode-map nil "s-0" +my/image-actual-size)
    (+my/image-mode-map nil "s-c" +my/image-copy)
    (+my/pdf-mode-map nil "s-=" +my/pdf-zoom-in)
    (+my/pdf-mode-map nil "s-c" +my/webkit-copy)
    (+my/pdf-mode-map nil "s-[" +my/pdf-back)
    (+my/pdf-mode-map nil "s-p" +my/pdf-print)
    (+md-preview-page-mode-map nil "s-c" +my/webkit-copy)
    (+my/merge-mode-map nil "s-s" +my/merge-done)
    (+my/merge-mode-map nil "C-c C-c" +my/merge-done))
  "(KEYMAP STATE KEY COMMAND): bound on macOS and on Linux. STATE: the Evil
state of KEYMAP's auxiliary map, or nil for KEYMAP itself.")

(defconst +test-keys--linux
  (append
   (cl-loop for n from 1 to 9
            for command = (intern (format "+my/tabs-select-%d" n))
            append (list (list 'global-map nil (format "C-%d" n) command)
                         (list 'evil-normal-state-map nil (format "C-%d" n) command)))
   '((global-map nil "C-S-w" +my/tabs-close-current)
     (global-map nil "C-S-b" +my/goto-declaration-or-usages)
     (evil-normal-state-map nil "M-<left>" better-jumper-jump-backward)
     (evil-normal-state-map nil "M-<right>" better-jumper-jump-forward)
     (evil-visual-state-map nil "M-<left>" better-jumper-jump-backward)
     (evil-motion-state-map nil "M-<right>" better-jumper-jump-forward)
     (global-map nil "C-S-f" +default/search-project)
     (evil-normal-state-map nil "C-S-f" +default/search-project)
     (+my/image-mode-map normal "C-=" +my/image-zoom-in)
     (+my/image-mode-map normal "C-+" +my/image-zoom-in)
     (+my/image-mode-map normal "C--" +my/image-zoom-out)
     (+my/image-mode-map normal "C-0" +my/image-actual-size)
     (+my/image-mode-map normal "C-S-c" +my/image-copy)
     (+my/pdf-mode-map normal "C-=" +my/pdf-zoom-in)
     (+my/pdf-mode-map motion "C-=" +my/pdf-zoom-in)
     (+my/pdf-mode-map normal "C-+" +my/pdf-zoom-in)
     (+my/pdf-mode-map normal "C--" +my/pdf-zoom-out)
     (+my/pdf-mode-map normal "C-0" +my/pdf-actual-size)
     (+my/pdf-mode-map normal "C-S-c" +my/webkit-copy)
     (+my/pdf-mode-map normal "C-p" +my/pdf-print)
     (+my/pdf-mode-map normal "M-<left>" +my/pdf-back)
     (+my/pdf-mode-map normal "M-<right>" +my/pdf-forward)
     (+md-preview-page-mode-map normal "C-S-c" +my/webkit-copy)
     (+my/merge-mode-map nil "C-s" +my/merge-done)))
  "(KEYMAP STATE KEY COMMAND): bound on Linux only (see above).")

(defun +test-keys--binding (spec)
  "What SPEC's (KEYMAP STATE KEY COMMAND) KEY is bound to now."
  (pcase-let* ((`(,map ,state ,key ,_) spec)
               (keymap (symbol-value map))
               (keymap (if state (evil-get-auxiliary-keymap keymap state) keymap)))
    (and (keymapp keymap)
         (let ((binding (lookup-key keymap (kbd key))))
           (and (not (numberp binding)) binding)))))

;; ====== LOADED AS ON MACOS, THEN AS ON LINUX ======

(+test-on-macos (apply #'+test-load +test-keys--files))

(defconst +test-keys--on-macos
  (mapcar (lambda (spec) (cons spec (+test-keys--binding spec)))
          (append +test-keys--everywhere +test-keys--linux))
  "What each key was bound to as on macOS.")

(+test-on-linux (apply #'+test-load +test-keys--files))

;; ====== TESTS ======

(ert-deftest keys/macos-has-the-cmd-keys ()
  (dolist (spec +test-keys--everywhere)
    (should (equal (list spec (cdr (assoc spec +test-keys--on-macos)))
                   (list spec (nth 3 spec))))))

(ert-deftest keys/macos-has-none-of-linuxs ()
  "On macOS Linux's keys are as they were (Doom's, Emacs's or none)."
  (dolist (spec +test-keys--linux)
    (should-not (eq (cdr (assoc spec +test-keys--on-macos)) (nth 3 spec)))))

(ert-deftest keys/linux-has-the-cmd-keys-too ()
  (dolist (spec +test-keys--everywhere)
    (should (equal (list spec (+test-keys--binding spec)) (list spec (nth 3 spec))))))

(ert-deftest keys/linux-has-its-own ()
  (dolist (spec +test-keys--linux)
    (should (equal (list spec (+test-keys--binding spec)) (list spec (nth 3 spec))))))

(ert-deftest keys/linux-keeps-vim-and-emacs-keys ()
  "Linux's keys take none of Vim's or Emacs's: C-b, C-w, C-c, C-v, C-o, C-i,
C-p (but a PDF's), C-s (but a merge's, a drawing's), M-1..9 (Doom's
workspaces)."
  (should (eq (lookup-key evil-motion-state-map (kbd "C-b")) #'evil-scroll-page-up))
  (should (keymapp (lookup-key evil-motion-state-map (kbd "C-w"))))
  (should (eq (lookup-key evil-normal-state-map (kbd "C-p")) #'evil-paste-pop))
  (should (eq (lookup-key evil-motion-state-map (kbd "C-v")) #'evil-visual-block))
  (should (eq (lookup-key evil-motion-state-map (kbd "C-o")) #'evil-jump-backward))
  (should-not (memq (lookup-key global-map (kbd "M-1")) '(+my/tabs-select-1)))
  (should-not (lookup-key global-map (kbd "C-S-c")))
  (should-not (lookup-key global-map (kbd "C-S-v")))
  ;; Insert state: Alt+← / Alt+→ still move by words.
  (should-not (lookup-key evil-insert-state-map (kbd "M-<left>")))
  (should (eq (lookup-key global-map (kbd "M-<left>")) #'left-word)))

(ert-deftest keys/labels-per-system ()
  (+test-on-macos
    (should (equal (+my/os-key-name "Cmd+C" "Ctrl+Shift+C") "Cmd+C"))
    (should (equal (+my/os-app-name 'viewer) "Preview"))
    (should (equal (+my/os-app-name 'files) "Finder")))
  (+test-on-linux
    (should (equal (+my/os-key-name "Cmd+C" "Ctrl+Shift+C") "Ctrl+Shift+C"))
    (should (equal (+my/os-app-name 'viewer) "the default app"))
    (should (equal (+my/os-app-name 'files) "the file manager"))))
