;;; tests/e2e/test-window.el -*- lexical-binding: t; -*-
;; config/window.el in a GUI Emacs, its commands run by the command loop (keys
;; typed): a command's new window selected once it ends; TAB's *Completions*
;; leaving the focus in the minibuffer, typing going on there; the right
;; fringe following the font.

(+test-load "config/window")

(defvar +test-window--map (make-sparse-keymap)
  "Keys for the commands below, typed.")

(defun +test-window--show-b ()
  "A command showing a buffer in a new window, then going on in its own."
  (interactive)
  (let ((before (current-buffer)))
    (display-buffer (get-buffer-create "*test b*") '(display-buffer-pop-up-window))
    ;; Still its own window and buffer.
    (unless (eq (current-buffer) before)
      (error "The current buffer changed under the command"))
    (recenter)))

(define-key +test-window--map (kbd "<f5>") #'+test-window--show-b)

(defun +test-window--type (keys)
  "KEYS typed, the command loop running their commands."
  (let ((overriding-terminal-local-map +test-window--map))
    (execute-kbd-macro (kbd keys))))

(ert-deftest e2e-window/a-command-s-new-window-selected-once-it-ends ()
  (+test-with-reset
    (let ((old (selected-window)))
      (+test-window--type "<f5>")
      (should-not (eq (selected-window) old))
      (should (equal (buffer-name (window-buffer)) "*test b*")))))

(ert-deftest e2e-window/completions-leave-the-focus-in-the-minibuffer ()
  "TAB at a prompt, *Completions* shown: the minibuffer still selected, what's
typed next goes on into it."
  (+test-with-reset
    (let* ((completion-auto-help t)
           (completion-auto-select nil)
           (shown nil)
           ;; Typing lost (the focus elsewhere): the prompt ended all the same.
           (timer (run-at-time 3 nil (lambda ()
                                       (when-let* ((window (active-minibuffer-window)))
                                         (with-selected-window window (exit-minibuffer))))))
           (answer
            (minibuffer-with-setup-hook
                (lambda ()
                  (add-hook 'post-command-hook
                            (lambda ()
                              (when (get-buffer-window "*Completions*")
                                (setq shown t)))
                            nil t))
              (let ((unread-command-events (listify-key-sequence (kbd "forward- TAB c RET"))))
                (completing-read "Command: " '("forward-char" "forward-line" "forward-word"))))))
      (cancel-timer timer)
      (should shown)
      (should (equal answer "forward-c")))))

(ert-deftest e2e-window/the-right-fringe-follows-the-font ()
  "Each font Doom sets (`after-setting-font-hook': at startup, after this file
loaded; doom/reload-font, big-font mode): the right fringe a character of it
wider than 8 pixels."
  (let ((height (face-attribute 'default :height)))
    (unwind-protect
        (dolist (new '(220 140))
          (set-face-attribute 'default nil :height new)
          (run-hooks 'after-setting-font-hook)
          (+test-sleep 0.1)
          (should (= (nth 1 (window-fringes)) (+ 8 (frame-char-width)))))
      (set-face-attribute 'default nil :height height)
      (run-hooks 'after-setting-font-hook))))
