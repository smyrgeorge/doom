;;; tests/e2e/test-large-files.el -*- lexical-binding: t; -*-
;; config/editor/large-files.el in a GUI Emacs: a 3 MB Markdown file with
;; very long lines (an agent-shell transcript's kind) and one of 60,000 short
;; lines, each opened and drawn within a second, light, with its notice laid
;; over the window (the banner's frame).
;; run.sh: alone. Its seconds are the clock's: beside other GUI Emacsen (on
;; GitHub's macOS runner, 3 cores, 4 at once) a 0.07 s opening took over 1 s.

(+test-load "config/childframe" "config/banner" "config/window" "config/editor")
(require 'so-long)
(require 'markdown-mode)
(global-so-long-mode 1)

(defun +test-lfe--open (file)
  "FILE opened (find-file) and drawn: the seconds it took."
  (let ((start (float-time)))
    (find-file file)
    (redisplay t)
    (- (float-time) start)))

(defmacro +test-lfe (&rest body)
  `(+test-with-reset
     (let ((auto-mode-alist (cons '("\\.md\\'" . markdown-mode) auto-mode-alist))
           (so-long-target-modes (append '(text-mode conf-mode) so-long-target-modes))
           (before (buffer-list)))
       (unwind-protect (progn ,@body)
         (dolist (b (buffer-list))
           (unless (memq b before)
             (with-current-buffer b
               (while +my/banner--list (+my/banner-close)))
             (kill-buffer b)))
         (+test-sleep 0.2)))))

(ert-deftest e2e-large-files/long-lines-at-once ()
  (+test-lfe
    (let* ((file (+test-file "large/transcript.md"
                             (with-temp-buffer
                               (dotimes (i 300)
                                 (insert (format "## Turn %d\n\n```elisp\n(setq a %d)\n```\n\n" i i))
                                 (when (zerop (% i 100)) (insert (make-string 19000 ?x) "\n\n"))
                                 (dotimes (_ 60) (insert (make-string 140 ?y) "\n")))
                               (buffer-string))))
           (seconds (+test-lfe--open file)))
      (should (< seconds 1))
      (should (eq major-mode 'so-long-mode))
      (should (assq 'long-lines +my/banner--list))
      (should (+test-wait-for (lambda () (assq (selected-window) +my/banner--frames)) 3)))))

(ert-deftest e2e-large-files/many-lines-at-once ()
  (+test-lfe
    (let* ((file (+test-file "large/notes.md"
                             (with-temp-buffer
                               (dotimes (i 60000) (insert (format "- item %d of the list\n" i)))
                               (buffer-string))))
           (seconds (+test-lfe--open file)))
      (should (< seconds 1))
      (should (eq major-mode 'markdown-mode))
      (should so-long-minor-mode)
      (should (string-match-p "This file is large" (nth 1 (assq 'large-file +my/banner--list))))
      ;; Scrolled through: drawn as it goes, no stall.
      (let ((start (float-time)))
        (goto-char (point-max))
        (redisplay t)
        (should (< (- (float-time) start) 1))))))
