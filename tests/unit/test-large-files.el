;;; tests/unit/test-large-files.el -*- lexical-binding: t; -*-
;; config/editor/large-files.el: files decided before their mode runs. Very
;; long lines: so-long-mode at once, the file's own mode never run (Open
;; normally runs it); a large file: its own mode without Doom's local-vars
;; hooks (the language server), so-long-minor-mode at once, the sticky header
;; and stripe off, a notice with Open normally. Generated files, in the temp
;; folder; Doom's MODE-local-vars-hook runner stood in for.

(+test-load "config/childframe" "config/banner" "config/editor")
(require 'so-long)
(require 'markdown-mode)

;; ====== HELPERS ======

(defvar +test-lf-ran nil "What ran while a file opened: mode hooks, local-vars hooks.")

(define-minor-mode +test-lf-heavy-mode "Stands in for the sticky header, the stripe." :init-value nil)

(defun +test-lf--local-vars-h ()
  "Doom's `doom-run-local-var-hooks-h', stood in for: its local-vars hooks
\(the language server), unless inhibited."
  (unless (bound-and-true-p doom-inhibit-local-var-hooks)
    (push (list 'local-vars major-mode) +test-lf-ran)))

(defmacro +test-lf (&rest body)
  "BODY from one window, Markdown files in markdown-mode (its hook noted, and
`+test-lf-heavy-mode' on in it), no notices' frames, icons standing in; the
files' buffers killed after."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+test-lf-ran nil)
           (+my/banner--frames nil)
           (auto-mode-alist (cons '("\\.md\\'" . markdown-mode) auto-mode-alist))
           ;; Doom's: text and config files too.
           (so-long-target-modes (append '(text-mode conf-mode) so-long-target-modes))
           (markdown-mode-hook (list (lambda () (push (list 'mode major-mode) +test-lf-ran))
                                     #'+test-lf-heavy-mode))
           (+my/large-files-modes-off (cons '+test-lf-heavy-mode +my/large-files-modes-off))
           (before (buffer-list)))
       (add-hook 'hack-local-variables-hook #'+test-lf--local-vars-h)
       (cl-letf (((symbol-function 'nerd-icons-codicon) (lambda (name) (upcase (substring name 7 8)))))
         (unwind-protect (progn ,@body)
           (remove-hook 'hack-local-variables-hook #'+test-lf--local-vars-h)
           (when (timerp +my/banner--sync-timer) (cancel-timer +my/banner--sync-timer))
           (setq +my/banner--sync-timer nil)
           (dolist (b (buffer-list))
             (unless (memq b before)
               (with-current-buffer b (set-buffer-modified-p nil))
               (kill-buffer b))))))))

(defun +test-lf--transcript ()
  "A 3 MB Markdown file like a long agent-shell transcript: code blocks, and a
few lines of 19,000 characters among short ones."
  (+test-file
   "large/transcript.md"
   (with-temp-buffer
     (dotimes (i 300)
       (insert (format "## Turn %d\n\nSome text about it.\n\n```elisp\n(setq a %d)\n```\n\n" i i))
       (when (zerop (% i 100))
         (insert (make-string 19000 ?x) "\n\n"))
       (dotimes (_ 60) (insert (make-string 140 ?y) "\n")))
     (buffer-string))))

(defun +test-lf--many-lines ()
  "A Markdown file of 60,000 short lines (~1.4 MB)."
  (+test-file "large/notes.md"
              (with-temp-buffer
                (dotimes (i 60000) (insert (format "- item %d of the list\n" i)))
                (buffer-string))))

(defun +test-lf--open (file)
  "FILE opened as find-file does, shown: its buffer, and the seconds it took."
  (let* ((start (float-time))
         (buffer (find-file-noselect file)))
    (switch-to-buffer buffer)
    (cons buffer (- (float-time) start))))

(defun +test-lf--notice (id)
  (assq id +my/banner--list))

;; ====== DECIDED BEFORE ======

(ert-deftest large-files/settings-and-wiring ()
  (should (= +my/large-file-size (* 1024 1024)))
  (should (= +my/large-file-ask-size (* 10 1024 1024)))
  (should (advice-member-p #'+my/large-files-set-auto-mode-a 'set-auto-mode))
  (should (advice-member-p #'+my/large-files-look-up-a 'set-auto-mode-0))
  (should (equal +my/large-files-modes-off '(+my/sticky-header-mode +my/stripe-mode))))

(ert-deftest large-files/what-kind ()
  "Long: a line over so-long's threshold; large: over the lines threshold or
the size; else, a temp buffer or one opened normally: nil."
  (cl-flet ((kind (text &optional name normally)
              (with-current-buffer (generate-new-buffer "x.md")
                (insert text)
                (setq buffer-file-name (or name "/tmp/x.md")
                      +my/large-files--normally normally)
                (prog1 (+my/large-files--kind)
                  (setq buffer-file-name nil)
                  (kill-buffer)))))
    (should (eq (kind (concat "a\n" (make-string 5001 ?x) "\n")) 'long))
    (should-not (kind (concat "a\n" (make-string 5000 ?x) "\n")))
    (should (eq (kind (apply #'concat (make-list 20001 "a\n"))) 'large))
    (should-not (kind (apply #'concat (make-list 20000 "a\n"))))
    (should (eq (kind (apply #'concat (make-list 11000 (concat (make-string 99 ?a) "\n")))) 'large))
    (should-not (kind (apply #'concat (make-list 20001 "a\n")) nil t))
    ;; Not a file's, or a temp buffer.
    (with-temp-buffer
      (insert (make-string 6000 ?x))
      (should-not (+my/large-files--kind))
      (setq buffer-file-name "/tmp/x.md")
      (should-not (+my/large-files--kind))
      (setq buffer-file-name nil))))

(ert-deftest large-files/long-lines-at-once ()
  "The transcript: so-long-mode within a second, markdown-mode never run (nor
its hooks), the long-lines notice; Open normally runs it."
  (+test-lf
    (pcase-let ((`(,buffer . ,seconds) (+test-lf--open (+test-lf--transcript))))
      (with-current-buffer buffer
        (should (> (buffer-size) 2500000))
        (should (< seconds 1))
        (should (eq major-mode 'so-long-mode))
        (should (eq (so-long-original 'major-mode) 'markdown-mode))
        ;; markdown-mode never ran, nor its hooks (so-long-mode's own did).
        (should-not (assoc 'mode +test-lf-ran))
        (should-not (member '(local-vars markdown-mode) +test-lf-ran))
        (should (string-search "up to 19,000 characters" (nth 1 (+test-lf--notice 'long-lines))))
        (should-not (+test-lf--notice 'large-file))
        (+my/long-lines--open-normally)
        (should (eq major-mode 'markdown-mode))
        (should (member '(mode markdown-mode) +test-lf-ran))
        (should (member '(local-vars markdown-mode) +test-lf-ran))))))

(ert-deftest large-files/large-light-at-once ()
  "60,000 short lines: its own mode, its hooks run, but not the local-vars ones
\(the language server); so-long-minor-mode at once; the heavy modes off; a
notice saying so, Open normally giving it all."
  (+test-lf
    (pcase-let ((`(,buffer . ,seconds) (+test-lf--open (+test-lf--many-lines))))
      (with-current-buffer buffer
        (should (< seconds 1))
        (should (eq major-mode 'markdown-mode))
        (should (member '(mode markdown-mode) +test-lf-ran))
        (should-not (assq 'local-vars +test-lf-ran))
        (should so-long-minor-mode)
        (should-not +test-lf-heavy-mode)
        (should (equal +my/large-file (cons (buffer-size) 60000)))
        (let ((notice (+test-lf--notice 'large-file)))
          (should (eq (nth 3 notice) 'warning))
          (should (string-match-p "\\`This file is large (1\\.[0-9] MB, 60,000 lines): opened without the language server, spelling, syntax checking, the sticky header and the error stripe"
                                  (nth 1 notice)))
          (should (equal (mapcar #'car (nth 2 notice)) '("Open normally")))
          (setq +test-lf-ran nil)
          (funcall (cdr (assoc "Open normally" (nth 2 notice)))))
        (should (eq major-mode 'markdown-mode))
        (should-not so-long-minor-mode)
        (should +test-lf-heavy-mode)
        ;; Its whole-buffer scan, done now (it was skipped).
        (should (>= syntax-propertize--done (point-max)))
        (should (member '(local-vars markdown-mode) +test-lf-ran))
        (should-not (+test-lf--notice 'large-file))
        ;; Opened again (reverted): normally still.
        (should-not (+my/large-files--kind))))))

(ert-deftest large-files/very-large-asks-first ()
  (+test-lf
    (let ((buffer (car (+test-lf--open (+test-lf--many-lines))))
          asked)
      (with-current-buffer buffer
        (let ((+my/large-file-ask-size 1000))
          (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) nil)))
            (+my/large-files-open-normally))
          (should (string-match-p "Open this 1\\.[0-9] MB file with everything on" (car asked)))
          (should so-long-minor-mode)
          (should (+test-lf--notice 'large-file)))))))

(ert-deftest large-files/others-as-before ()
  "A small file: its mode, nothing off, no notice. A large file of no code,
text or config mode: as it opens."
  (+test-lf
    (with-current-buffer (car (+test-lf--open (+test-file "large/small.md" "# Hi\n\nShort.\n")))
      (should (eq major-mode 'markdown-mode))
      (should-not (bound-and-true-p so-long-minor-mode))
      (should +test-lf-heavy-mode)
      (should (member '(local-vars markdown-mode) +test-lf-ran))
      (should-not +my/banner--list))
    (let ((auto-mode-alist (cons '("\\.dat\\'" . hexl-mode) auto-mode-alist)))
      (with-current-buffer (car (+test-lf--open (+test-file "large/blob.dat" (make-string 1200000 ?z))))
        (should (eq major-mode 'hexl-mode))
        (should-not +my/large-file)
        (should-not +my/banner--list)))))
