;;; tests/helper-beads.el -*- lexical-binding: t; -*-
;; What test-beads*.el share: config/beads.el loaded (beads.el, mended for
;; bd 1.x, not with it), a temp git repo with a temp HOME made a bd project
;; (`+test-bd-init', tests/helper.el: one bd init copied), the real bd run in
;; it; the list's rows, bar, notices read back. Each test-beads*.el file runs
;; in an Emacs of its own, side by side (tests/run.sh): split for that.

;; ====== LOADING ======

(load (expand-file-name "beads-autoloads"
                        (file-name-directory (locate-library "beads")))
      nil t)
(+test-load "config/window" "config/tiling" "config/childframe" "config/banner" "config/beads")

(defconst +test-beads--loaded-before (featurep 'beads)
  "Whether loading config/beads.el loaded beads.el (it mustn't).")

(require 'beads)
(require 'beads-stale)
(require 'beads-lint)
(require 'beads-hierarchy)
(require 'beads-activity)               ; its faces
(require 'doom-themes)                  ; doom-blend
(require 'nerd-icons)                   ; the types' icons
(require 'markdown-mode)                ; an issue's text as Markdown

;; ====== HELPERS ======

(defun +test-beads--run (program &rest args)
  "PROGRAM's output with ARGS in `default-directory' (an error if it failed)."
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t nil args)))
      (unless (zerop status)
        (error "%s %s: %s" program (string-join args " ") (buffer-string)))
      (buffer-string))))

(defmacro +test-beads-with-repo (&rest body)
  "BODY in a new git repo (`default-directory', also `repo'), with a temp HOME
and global gitconfig, Doom's project root it; skipped without bd. One window
on *scratch*, and again after (Beads' buffers killed). Lists drawn wide
\(with their ids), however narrow their pane: the batch frame's 80 columns,
halved by tiling, are narrow (see `beads/bd-a-narrow-pane-the-title-s-room')."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd")
       (ert-skip "No bd (scripts/tools.sh installs it)"))
     (+test-with-reset
       (let* ((+my/beads--narrow-width 0)
              (home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
              (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
              (process-environment
               (append (list (concat "HOME=" home)
                             (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                             "GIT_CONFIG_NOSYSTEM=1"
                             (concat "XDG_CONFIG_HOME=" home ".config")
                             "BD_ACTOR=Tester")
                       process-environment))
              (default-directory repo))
         ;; Doom's project root (projectile's, not loaded here): the repo.
         (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
           (with-temp-file (expand-file-name ".gitconfig" home)
             (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                     "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
           (+test-beads--run "git" "init" "-q")
           (unwind-protect (progn ,@body)
             (dolist (buffer (buffer-list))
               (when (string-prefix-p "*Beads" (buffer-name buffer))
                 (kill-buffer buffer)))))))))

(defmacro +test-beads-with-project (&rest body)
  "BODY in a new git repo tracking its issues with bd (see
`+test-beads-with-repo')."
  (declare (indent 0))
  `(+test-beads-with-repo
     (+test-bd-init "--quiet" "--prefix" "t")
     ,@body))

(defun +test-beads--create (title &rest args)
  "A new issue TITLE (with ARGS, as `beads-client-create' takes them): its id."
  (alist-get 'id (apply #'beads-client-create title args)))

(defun +test-beads--text (buffer)
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-beads--list ()
  "The issue list's buffer."
  (seq-find (lambda (b) (with-current-buffer b (derived-mode-p 'beads-list-mode)))
            (buffer-list)))

(defun +test-beads--settle (buffer &optional seconds)
  "Wait (SECONDS at most, else 30) for BUFFER's refresh on its way to end."
  (let ((end (+ (float-time) (or seconds 30))))
    (while (and (buffer-local-value '+my/beads--fetching buffer) (< (float-time) end))
      (accept-process-output nil 0.05))
    (should-not (buffer-local-value '+my/beads--fetching buffer))))

(defun +test-beads--slow-bd (seconds &optional code)
  "A stand-in bd: sleeps SECONDS, then runs the real one (or fails with CODE)."
  (let ((script (make-temp-file (+test-tmp-file "slow-bd-"))))
    (with-temp-file script
      (insert "#!/bin/sh\nsleep " (number-to-string seconds) "\n"
              (if code
                  (format "echo 'bd broke' >&2\nexit %d\n" code)
                (format "exec %s \"$@\"\n" (shell-quote-argument (executable-find "bd"))))))
    (set-file-modes script #o755)
    script))

(defun +test-beads--bar ()
  "The current issue list's bottom bar in full (as in a wide window), its
counts."
  (substring-no-properties (+my/beads--bar 1000)))

(defun +test-beads--bulk (open closed)
  "OPEN + CLOSED new issues (t-1...), imported into bd at once: the first
CLOSED closed, the others open (P2 tasks). Not made one by one (slow), nor by
bd create -f: its short ids, chosen at random, can clash among a hundred."
  (let ((file (make-temp-file (+test-tmp-file "issues-") nil ".jsonl"
                              (mapconcat
                               (lambda (i)
                                 (json-encode
                                  `((id . ,(format "t-%d" i)) (title . ,(format "Issue %d" i))
                                    (status . ,(if (<= i closed) "closed" "open"))
                                    (priority . 2) (issue_type . "task")
                                    (created_at . "2026-11-01T10:00:00Z")
                                    (updated_at . "2026-11-01T10:00:00Z")
                                    ,@(and (<= i closed) '((closed_at . "2026-11-02T10:00:00Z"))))))
                               (number-sequence 1 (+ open closed)) "\n"))))
    (+test-beads--run "bd" "import" file "--quiet")))

(defun +test-beads--rows ()
  "How many issues the current list shows."
  (save-excursion
    (goto-char (point-min))
    (let ((rows 0))
      (while (not (eobp))
        (when (tabulated-list-get-id) (cl-incf rows))
        (forward-line 1))
      rows)))

(defun +test-beads--notices ()
  "The current buffer's notices: (TEXT ACTION-LABELS) each."
  (mapcar (lambda (notice) (list (nth 1 notice) (mapcar #'car (nth 2 notice))))
          +my/banner--list))

(defun +test-beads--press (label)
  "The notice action LABEL, pressed."
  (let ((action (seq-some (lambda (notice) (assoc label (nth 2 notice))) +my/banner--list)))
    (should action)
    (funcall (cdr action))))

(defun +test-beads--line (text)
  "The current list's line showing TEXT, its text."
  (save-excursion
    (goto-char (point-min))
    (and (search-forward text nil t)
         (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))

(defun +test-beads--width (window columns)
  "WINDOW resized to COLUMNS of body, and told so (batch Emacs runs no
window change functions: called as redisplay calls them)."
  (unless (= (window-body-width window) columns)
    (window-resize window (- columns (window-body-width window)) t))
  (should (= (window-body-width window) columns))
  (with-current-buffer (window-buffer window)
    (run-hook-with-args 'window-size-change-functions window)))
