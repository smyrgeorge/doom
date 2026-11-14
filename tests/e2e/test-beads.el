;;; tests/e2e/test-beads.el -*- lexical-binding: t; -*-
;; config/beads.el in a GUI Emacs: the issue list's notices (what it hides)
;; laid over its column titles by the banner's child frame, the titles kept in
;; the row under them; an issue's view in narrow panes, on screen. The real bd
;; (skipped without it), in a temp git repo with a temp HOME.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/childframe" "config/banner" "config/window" "config/tiling" "config/beads")
(require 'beads)

(defun +test-beads-e2e--run (program &rest args)
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (error "%s %s: %s" program (string-join args " ") (buffer-string)))))

(ert-deftest e2e-beads/the-notice-over-the-column-titles ()
  (unless (executable-find "bd")
    (ert-skip "No bd (scripts/tools.sh installs it)"))
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
           (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
           (process-environment
            (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                          "GIT_CONFIG_NOSYSTEM=1" (concat "XDG_CONFIG_HOME=" home ".config")
                          "BD_ACTOR=Tester")
                    process-environment))
           (default-directory repo))
      (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
        (with-temp-file (expand-file-name ".gitconfig" home)
          (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                  "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
        (+test-beads-e2e--run "git" "init" "-q")
        (+test-beads-e2e--run "bd" "init" "--quiet" "--prefix" "t")
        (+test-beads-e2e--run "bd" "create" "Still open" "--quiet")
        (+test-beads-e2e--run "bd" "close" (string-trim (with-temp-buffer
                                                         (call-process "bd" nil t nil "create" "Done" "--silent")
                                                         (buffer-string)))
                              "--quiet")
        (unwind-protect
            (progn
              (+my/beads-project)
              (let* ((window (selected-window))
                     (row (+my/banner--row-height window))
                     (frame (+test-wait-for
                             (lambda ()
                               (let ((frame (nth 1 (assq window +my/banner--frames))))
                                 (and (frame-live-p frame) (+my/childframe-shown-p frame) frame)))
                             5)))
                (should (derived-mode-p 'beads-list-mode))
                (should frame)
                (should (string-match-p "1 closed issue hidden"
                                        (with-current-buffer (window-buffer (frame-root-window frame))
                                          (buffer-string))))
                ;; Over the window's top row; the header line two rows tall
                ;; once drawn (the list is shown before it's drawn: its
                ;; window's height known until then is the empty list's), the
                ;; column titles in its bottom one, visible.
                (should (+test-wait-for
                         (lambda ()
                           (and (= (cdr (frame-position frame))
                                   (+ (nth 1 (window-pixel-edges window)) (window-tab-line-height window)))
                                (= (frame-pixel-height frame) row)))
                         3))
                (should (+test-wait-for (lambda () (>= (window-header-line-height window) (* 2 row))) 3))
                (should (string-match-p "Title" (format-mode-line header-line-format nil window)))))
          (dolist (buffer (buffer-list))
            (when (string-prefix-p "*Beads" (buffer-name buffer))
              (kill-buffer buffer)))
          (+test-sleep 0.2))))))

(defmacro +test-beads-e2e-with-project (&rest body)
  "BODY in a new git repo tracking its issues with bd (`default-directory',
also `repo'), a temp HOME; skipped without bd. Beads' buffers killed after."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd")
       (ert-skip "No bd (scripts/tools.sh installs it)"))
     (+test-with-reset
       (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
              (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
              (process-environment
               (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                             "GIT_CONFIG_NOSYSTEM=1" (concat "XDG_CONFIG_HOME=" home ".config")
                             "BD_ACTOR=Tester")
                       process-environment))
              (default-directory repo))
         (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
           (with-temp-file (expand-file-name ".gitconfig" home)
             (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                     "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
           (+test-beads-e2e--run "git" "init" "-q")
           (+test-beads-e2e--run "bd" "init" "--quiet" "--prefix" "t")
           (unwind-protect (progn ,@body)
             (dolist (buffer (buffer-list))
               (when (string-prefix-p "*Beads" (buffer-name buffer))
                 (kill-buffer buffer)))
             (+test-sleep 0.2)))))))

(defun +test-beads-e2e--row (window pos)
  "The screen row of POS in WINDOW."
  (cdr (posn-col-row (posn-at-point pos window))))

;; doom-o5t.14
(ert-deftest e2e-beads/an-issue-in-a-narrow-pane ()
  "An issue's view in a pane of 60, 40, 25 columns: each rule one screen line
\(beads.el's, 60 characters: two at 40, three at 25); each [edit] on its
field's line (beside the next field's name at 25), on its screen line too
where there's room; a long line of its description going on under itself
\(at the pane's edge)."
  (+test-beads-e2e-with-project
    (let* ((truncate-partial-width-windows nil) ; Doom's
           (id (with-temp-buffer
                 (call-process "bd" nil t nil "create" "An issue read in a narrow pane" "--silent"
                               "--description" (concat "A line long enough to go on to the next ones in a"
                                                       " narrow pane, at a word, under its own start.\n\n"
                                                       "- an item of a list, as long, going on under its text"))
                 (string-trim (buffer-string)))))
      (+test-beads-e2e--run "bd" "update" id "--status" "in_progress" "--quiet")
      (beads-detail-open (beads-client-show id))
      (let* ((buffer (get-buffer (format "*Beads Detail: %s*" id)))
             (window (get-buffer-window buffer)))
        (delete-other-windows window)
        (set-window-buffer (split-window window nil 'right) (get-buffer-create "*scratch*"))
        (dolist (width '(60 40 25))
          (window-resize window (- width (window-body-width window)) t)
          (should (= (window-body-width window) width))
          (with-current-buffer buffer
            ;; Drawn again for its width (vui's, on a resize).
            (should (+test-wait-for
                     (lambda ()
                       (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "^═+$" nil t)
                              (= (- (match-end 0) (match-beginning 0)) (1- width)))))
                     5))
            (+test-sleep 0.2)
            (save-excursion
              ;; Each rule one screen line.
              (goto-char (point-min))
              (let ((rules 0))
                (while (re-search-forward "^\\([═─]\\)\\1+$" nil t)
                  (cl-incf rules)
                  (should (= (count-screen-lines (match-beginning 0) (match-end 0) nil window) 1)))
                (should (>= rules 2)))
              ;; Each [edit] after its field's name on its line, beside it on
              ;; the screen where there's room.
              (goto-char (point-min))
              (re-search-forward "^Status:")
              (let ((end (save-excursion (re-search-forward "^─+$"))))
                (while (re-search-forward "\\[edit\\]" end t)
                  (let ((edit (match-beginning 0)))
                    (save-excursion
                      (should (re-search-backward "\\(Status\\|Priority\\|Type\\|Assignee\\):" nil t))
                      (should (= (line-number-at-pos) (line-number-at-pos edit)))
                      (when (>= width 40)
                        (should (= (+test-beads-e2e--row window (point))
                                   (+test-beads-e2e--row window edit))))))))
              ;; The description's long line: its next screen lines under it.
              (goto-char (point-min))
              (search-forward "A line long enough")
              (goto-char (match-beginning 0))
              (let ((indent (car (posn-x-y (posn-at-point (point) window)))))
                (should (> indent 0))
                (vertical-motion 1 window)
                (should (= (car (posn-x-y (posn-at-point (point) window))) indent))))))))))
