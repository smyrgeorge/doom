;;; tests/unit/test-long-lines.el -*- lexical-binding: t; -*-
;; config/long-lines.el: files with very long lines open plain (so-long-mode,
;; unwrapped), with a notice (config/banner.el's) saying so; its actions wrap
;; the lines, or open the file normally.

(+test-load "config/childframe" "config/banner" "config/long-lines")
(require 'so-long)

;; ====== HELPERS ======

(defmacro +test-long-lines (&rest body)
  "BODY from one window on *scratch*, no notices' frames, icons standing in."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+my/banner--frames nil))
       (cl-letf (((symbol-function 'nerd-icons-codicon)
                  (lambda (name) (upcase (substring name 7 8)))))
         (unwind-protect (progn ,@body)
           (when (timerp +my/banner--sync-timer)
             (cancel-timer +my/banner--sync-timer))
           (setq +my/banner--sync-timer nil))))))

(defun +test-long-lines--file ()
  "A buffer visiting an Emacs Lisp file with a 20,000 characters long line."
  (find-file-noselect
   (+test-file "long.el" (concat ";; " (make-string 19997 ?x) "\n(setq a 1)\n"))))

(defun +test-long-lines--click (buffer label)
  "Click LABEL in the long lines notice's row of BUFFER."
  (let* ((row (+my/banner--row (assq 'long-lines (buffer-local-value '+my/banner--list buffer)) buffer))
         (pos (or (string-search label row) (error "No %S in %S" label row))))
    (call-interactively (lookup-key (get-text-property pos 'keymap row) [mouse-1]))))

;; ====== OPENED PLAIN ======

(ert-deftest long-lines/settings ()
  "Lines over 5,000 characters count as very long; so-long-mode doesn't wrap them."
  (should (= +my/long-line-threshold 5000))
  (should (= so-long-threshold +my/long-line-threshold))
  (should (eq (alist-get 'truncate-lines so-long-variable-overrides) t)))

(ert-deftest long-lines/open-plain-and-unwrapped ()
  "With Doom's global-so-long-mode: a file with a line over the threshold opens in
so-long-mode (once shown in a window), unwrapped; one at the threshold in its own
mode."
  (+test-with-reset
    (let ((was global-so-long-mode))
      (unwind-protect
          (progn
            (global-so-long-mode 1)
            (find-file (+test-file "long-lines/report.py"
                                   (concat "x = 1\ndata = '" (make-string 5001 ?a) "'\n")))
            (run-window-configuration-change-hook)  ; as redisplay would
            (should (eq major-mode 'so-long-mode))
            (should truncate-lines)
            (find-file (+test-file "long-lines/ok.py" (concat (make-string 5000 ?a) "\n")))
            (run-window-configuration-change-hook)
            (should (eq major-mode 'python-mode))
            (should-not truncate-lines))
        (global-so-long-mode (if was 1 -1))))))

;; ====== THE NOTICE ======

(ert-deftest long-lines/group-digits ()
  (should (equal (+my/long-lines--group-digits 0) "0"))
  (should (equal (+my/long-lines--group-digits 7) "7"))
  (should (equal (+my/long-lines--group-digits 999) "999"))
  (should (equal (+my/long-lines--group-digits 1000) "1,000"))
  (should (equal (+my/long-lines--group-digits 51997) "51,997"))
  (should (equal (+my/long-lines--group-digits 100000) "100,000"))
  (should (equal (+my/long-lines--group-digits 1234567) "1,234,567"))
  (should (equal (+my/long-lines--group-digits 1000000000) "1,000,000,000")))

(ert-deftest long-lines/notice ()
  "Opened in `so-long-mode' (unwrapped): a warning with the longest line's
length, and the ways back."
  (+test-long-lines
    (with-current-buffer (+test-long-lines--file)
      (so-long)
      (should (derived-mode-p 'so-long-mode))
      (should truncate-lines)
      (let ((notice (assq 'long-lines +my/banner--list)))
        (should notice)
        (should (eq (nth 3 notice) 'warning))
        (should (string-search "up to 20,000 characters" (nth 1 notice)))
        (should (string-search "without highlighting and unwrapped" (nth 1 notice)))
        (should (equal (mapcar #'car (nth 2 notice)) '("Wrap lines" "Open normally")))))))

(ert-deftest long-lines/notice-when-wrapped ()
  (+test-long-lines
    (with-current-buffer (+test-long-lines--file)
      (so-long)
      (setq-local truncate-lines nil)
      (+my/long-lines-notice-h)
      (let ((notice (assq 'long-lines +my/banner--list)))
        (should (= (length +my/banner--list) 1))
        (should-not (string-search "unwrapped" (nth 1 notice)))
        (should (equal (mapcar #'car (nth 2 notice)) '("Open normally")))))))

(ert-deftest long-lines/hooks ()
  (should (memq '+my/long-lines-notice-h so-long-hook)))

(ert-deftest long-lines/notice-only-in-so-long-mode ()
  (+test-long-lines
    (with-current-buffer (+test-buffer "B" (make-string 30000 ?x) #'text-mode)
      (+my/long-lines-notice-h)
      (should-not +my/banner--list))))

(ert-deftest long-lines/wrap-lines-action ()
  "Wrap lines: the lines wrap, the notice stays without that action."
  (+test-long-lines
    (let ((buffer (+test-long-lines--file)))
      (switch-to-buffer buffer)
      (so-long)
      (setq-local truncate-lines t)
      (+my/banner-show 'other "Another")
      (+my/long-lines-notice-h)
      (+test-long-lines--click buffer "Wrap lines")
      (should-not (buffer-local-value 'truncate-lines buffer))
      (with-current-buffer buffer
        ;; In its place, before the one shown after it.
        (should (equal (mapcar #'car +my/banner--list) '(long-lines other)))
        (let ((notice (assq 'long-lines +my/banner--list)))
          (should (equal (mapcar #'car (nth 2 notice)) '("Open normally")))
          (should-not (string-search "unwrapped" (nth 1 notice))))))))

(ert-deftest long-lines/open-normally-action ()
  "Open normally: the file's own mode back, the notice gone."
  (+test-long-lines
    (let ((buffer (+test-long-lines--file)))
      (switch-to-buffer buffer)
      (should (eq major-mode 'emacs-lisp-mode))
      (so-long)
      (should (eq major-mode 'so-long-mode))
      (+test-long-lines--click buffer "Open normally")
      (with-current-buffer buffer
        (should (eq major-mode 'emacs-lisp-mode))
        (should-not +my/banner--list)
        (should-not (+my/banner--ours-p))))))

;; ====== LOADED ======

(ert-deftest long-lines/config-el-loads-it-after-banner ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (setq forms (nreverse forms))
      (should (< (seq-position forms '(load! "config/banner"))
                 (seq-position forms '(load! "config/long-lines")))))))
