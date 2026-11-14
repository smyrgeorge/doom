;;; $DOOMDIR/config/merge/session.el -*- lexical-binding: t; -*-
;; A merge opened, one file after another, closed. Loaded from config/merge.el.

;; OPENING
(defun +my/merge--pane (name text mode-file &optional editable)
  "A pane's buffer NAME with TEXT, in the mode MODE-FILE's name gives (its
hooks not run: no language server, linter...), read-only unless EDITABLE."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer
      (insert text)
      (goto-char (point-min))
      (let ((buffer-file-name (expand-file-name mode-file)))
        (delay-mode-hooks
          (ignore-errors (set-auto-mode))))
      (font-lock-mode 1)
      ;; Its own line numbers (see LINE NUMBERS, align.el), not Emacs's.
      (display-line-numbers-mode -1)
      (jit-lock-register #'+my/merge--number)
      (set-buffer-modified-p nil)
      (setq buffer-read-only (not editable))
      ;; The margins (buttons, the wand) by the code, the fringes at the
      ;; window's edges: each side's buttons as far from its code (Doom's
      ;; vc-gutter makes it so everywhere; not everyone has it).
      (setq-local fringes-outside-margins t)
      ;; Only the Result's edits are undone (the others' are fillers).
      (unless editable
        (buffer-disable-undo))
      (when (fboundp '+my/tabs-off-h)
        (+my/tabs-off-h)))
    buffer))

(defun +my/merge--layout (session)
  "SESSION's panes: the bar across the top, Yours, the Result (selected),
Theirs."
  (let ((window-min-height 1)
        (window-safe-min-height 1)
        (window-min-width 10))
    (when (window-parameter nil 'window-side)
      (select-window (window-main-window)))
    (delete-other-windows)
    (let* ((left (selected-window))
           (bar (split-window left -2 'above))
           (middle (split-window left (- (* 2 (/ (window-total-width left) 3))) 'right))
           (right (split-window middle (- (/ (window-total-width middle) 2)) 'right)))
      (set-window-buffer bar (+my/merge-bar session))
      (set-window-dedicated-p bar t)
      (set-window-parameter bar 'no-other-window t)
      (set-window-parameter bar 'no-delete-other-windows t)
      (fit-window-to-buffer bar 1 1)
      (window-preserve-size bar nil t)
      (pcase-dolist (`(,window ,buffer ,margin) `((,left ,(+my/merge-yours session) right)
                                                   (,middle ,(+my/merge-result session) nil)
                                                   (,right ,(+my/merge-theirs session) left)))
        (set-window-buffer window buffer)
        (set-window-margins window (pcase margin ('left (+my/merge--theirs-margin-columns)) ('nil 2))
                            (and (eq margin 'right) (+my/merge--yours-margin-columns)))
        (set-window-start window (point-min))
        (set-window-prev-buffers window nil))
      (select-window middle)
      (dolist (window (list left middle right))
        (set-window-parameter window '+my/merge-view (+my/merge--view window)))
      (list left middle right bar))))

(defun +my/merge--start (path)
  "Resolve PATH's conflict (relative to the repository's top, the current
folder) in three panes."
  (let* ((bytes (mapcar (lambda (stage) (+my/merge--blob stage path)) '(1 2 3)))
         (coding (+my/merge--coding (nth 1 bytes)))
         (texts (mapcar (lambda (b) (decode-coding-string b coding)) bytes))
         (labels (+my/merge--labels))
         (session (+my/merge--make :path path :toplevel default-directory :coding coding
                                   :labels labels :frame (selected-frame)
                                   :winconf (current-window-configuration))))
    (setf (+my/merge-base session) (+my/merge--pane (format " *merge base: %s*" path) (nth 0 texts) path)
          (+my/merge-yours session) (+my/merge--pane (format "Yours: %s" path) (nth 1 texts) path)
          (+my/merge-theirs session) (+my/merge--pane (format "Theirs: %s" path) (nth 2 texts) path)
          (+my/merge-result session) (+my/merge--pane (format "Result: %s" path) (nth 0 texts) path t)
          (+my/merge-bar session) (generate-new-buffer (format " *merge: %s*" path)))
    (setf (+my/merge-chunks session) (+my/merge--chunks session))
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-theirs session)
                          (+my/merge-result session) (+my/merge-base session)
                          (+my/merge-bar session)))
      (with-current-buffer buffer
        (setq +my/merge--session session)
        (setq default-directory (+my/merge-toplevel session))
        (add-hook 'kill-buffer-hook #'+my/merge--killed-h nil t)))
    (with-current-buffer (+my/merge-bar session)
      (+my/merge-bar-mode)
      (setq +my/merge--session session)
      (add-hook 'kill-buffer-hook #'+my/merge--killed-h nil t)
      (add-hook 'window-size-change-functions #'+my/merge--bar-resized-h nil t))
    (pcase-dolist (`(,buffer ,title) `((,(+my/merge-yours session) ,(concat "Yours: " (car labels)))
                                       (,(+my/merge-result session) ,(concat "Result: " path))
                                       (,(+my/merge-theirs session) ,(concat "Theirs: " (cdr labels)))))
      (with-current-buffer buffer
        ;; First: turned off, it puts back the buffer's `truncate-lines'.
        (when (bound-and-true-p visual-line-mode)
          (visual-line-mode -1))
        (setq-local header-line-format (concat " " (propertize title 'face 'bold))
                    ;; A row a line: lined up (see LINING UP, align.el).
                    truncate-lines t
                    filter-buffer-substring-function #'+my/merge--filter-substring)
        (cursor-intangible-mode 1)
        (add-hook 'after-change-functions #'+my/merge--changed-h nil t)
        (add-hook 'post-command-hook #'+my/merge--post-command-h nil t)
        (+my/merge-mode 1)))
    (with-current-buffer (+my/merge-result session)
      (setq buffer-undo-list nil))
    (+my/merge--refine session)
    (seq-doseq (chunk (+my/merge-chunks session))
      (setf (+my/merge-chunk-wand chunk) (+my/merge--wand-of chunk))
      (+my/merge--render-chunk chunk))
    (with-current-buffer (+my/merge-result session)
      (let ((buffer-undo-list t))
        (+my/merge--align session)))
    (+my/merge--layout session)
    (+my/merge--render-bar session)
    ;; At the first change.
    (when-let* ((first (seq-first (+my/merge-chunks session))))
      (+my/merge--goto first))
    (message "%s: %s" path (with-current-buffer (+my/merge-bar session)
                              (string-trim (buffer-string))))
    session))

(defun +my/merge (file)
  "Resolve FILE's conflicts in three panes: Yours, the Result, Theirs (see
config/merge.el); Magit's Ediff for what they can't show."
  (interactive (progn (require 'magit) (list (magit-read-unmerged-file))))
  (require 'magit)
  ;; Magit's functions, not its macros (`magit-with-toplevel'): compiled
  ;; before Magit loaded (config/emacs/compile.el), a macro is a call to
  ;; nothing the first time.
  (let* ((default-directory (or (magit-toplevel) (user-error "Not in a Git repository")))
         (path (file-relative-name (expand-file-name file) default-directory))
         (why (+my/merge--why-not path)))
    (cond ((not why) (+my/merge--start path))
          ((equal why "Not in conflict") (user-error "%s has no conflict" path))
          (t (message "%s: %s, so Ediff" path why)
             (magit-ediff-resolve-rest path)))))

;; ONE FILE AFTER THE OTHER
(defvar +my/merge--then nil
  "((SESSION . FUNCTION)...): FUNCTION to call once SESSION is closed.")

(defun +my/merge-then (session function)
  "Call FUNCTION (no arguments) once SESSION's merge is closed (done,
aborted)."
  (push (cons session function) +my/merge--then)
  (add-hook '+my/merge-finished-functions #'+my/merge--then-h))

(defun +my/merge--then-h (session)
  (when-let* ((entry (assq session +my/merge--then)))
    (setq +my/merge--then (delq entry +my/merge--then))
    ;; After the merge's windows are back, not inside its closing.
    (run-at-time 0 nil (cdr entry))))

(defun +my/merge-files (files &optional then)
  "Resolve FILES' conflicts in the panes, one after the other, each in its own
repository; then THEN, a function of the files still in conflict. Files the
panes can't show (not in conflict, binary...) are skipped, said why."
  (require 'magit)
  (let ((queue (mapcar #'expand-file-name files))
        (frame (selected-frame))
        (skipped nil))
    (cl-labels
        ((left ()
           (seq-filter (lambda (file)
                         (let ((default-directory (file-name-directory file)))
                           (and (magit-toplevel)
                                (+my/merge--stages (file-relative-name file (magit-toplevel))))))
                       (mapcar #'expand-file-name files)))
         (next ()
           ;; Its frame closed: no more.
           (unless (frame-live-p frame)
             (setq queue nil))
           (when (frame-live-p frame)
             (select-frame frame))
           (if (null queue)
               (progn (when skipped
                        (message "Skipped: %s" (string-join (nreverse skipped) "; ")))
                      (when then (funcall then (left))))
             (let* ((file (pop queue))
                    (default-directory (file-name-directory file))
                    (top (magit-toplevel))
                    (why (if top
                             (+my/merge--why-not (file-relative-name file top))
                           "Not in a Git repository")))
               (if why
                   (progn (push (format "%s (%s)" (file-name-nondirectory file) why) skipped)
                          (next))
                 (condition-case err
                     (+my/merge-then (+my/merge file) #'next)
                   (error (push (format "%s (%s)" (file-name-nondirectory file) (error-message-string err))
                                skipped)
                          (next))))))))
      (next))))

(defun +my/merge-all ()
  "Resolve each conflicted file of the repository in the panes, one after the
other (see `+my/merge-files')."
  (interactive)
  (require 'magit)
  (let* ((default-directory (or (magit-toplevel) (user-error "Not in a Git repository")))
         (files (magit-unmerged-files)))
    (unless files
      (user-error "No conflicts here"))
    (+my/merge-files (mapcar #'expand-file-name files)
                     (lambda (left)
                       (message "%s" (if left
                                         (format "Still in conflict: %s"
                                                 (string-join (mapcar #'file-relative-name left) ", "))
                                       "All conflicts resolved"))))))

;; CLOSING
(defun +my/merge--session ()
  (or +my/merge--session (user-error "Not in a merge")))

(defun +my/merge--finish (session)
  "Close SESSION: its panes, the windows as they were."
  (unless (+my/merge-finished session)
    (setf (+my/merge-finished session) t)
    (when (+my/merge-winconf session)
      (ignore-errors (set-window-configuration (+my/merge-winconf session))))
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-theirs session)
                          (+my/merge-result session) (+my/merge-base session)
                          (+my/merge-bar session)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))
    (when (fboundp 'magit-refresh-all)
      (let ((default-directory (+my/merge-toplevel session)))
        (ignore-errors (magit-refresh-all))))
    (run-hook-with-args '+my/merge-finished-functions session)))

(defun +my/merge--frame-deleted-h (frame)
  "FRAME deleted (a terminal's frame closed): its merges, aborted."
  (dolist (buffer (buffer-list))
    (when-let* ((session (buffer-local-value '+my/merge--session buffer))
                ((eq (+my/merge-frame session) frame))
                ((not (+my/merge-finished session))))
      (setf (+my/merge-winconf session) nil)    ; its windows are gone
      (+my/merge--finish session))))

(add-hook 'delete-frame-functions #'+my/merge--frame-deleted-h)

(defun +my/merge--killed-h ()
  "A pane closed (Cmd+W, say): the merge with it, aborted."
  (when (and +my/merge--session (not (+my/merge-finished +my/merge--session)))
    (let ((session +my/merge--session))
      (run-at-time 0 nil #'+my/merge--finish session))))

(defun +my/merge--markers (session)
  "SESSION's Result, the changes not done as conflict markers (Git's)."
  (with-current-buffer (+my/merge-result session)
    (let ((labels (+my/merge-labels session))
          (line (lambda (text) (if (or (string-empty-p text) (string-suffix-p "\n" text))
                                   text (concat text "\n"))))
          (pos (point-min))
          (parts nil))
      (seq-doseq (chunk (+my/merge-chunks session))
        (unless (+my/merge--resolved-p chunk)
          (let ((ov (+my/merge-chunk-result chunk)))
            (push (+my/merge--clean pos (overlay-start ov)) parts)
            (push (concat "<<<<<<< " (car labels) "\n"
                          (funcall line (+my/merge--side-text chunk 'yours))
                          "=======\n"
                          (funcall line (+my/merge--side-text chunk 'theirs))
                          ">>>>>>> " (cdr labels) "\n")
                  parts)
            (setq pos (overlay-end ov)))))
      (push (+my/merge--clean pos (point-max)) parts)
      (apply #'concat (nreverse parts)))))

(defun +my/merge--result-text (session)
  "SESSION's Result, as it'll be saved (without fillers)."
  (with-current-buffer (+my/merge-result session)
    (+my/merge--clean (point-min) (point-max))))

(defun +my/merge--write (session text)
  "Write TEXT to SESSION's file, as is (no save hooks: formatting...); a
buffer visiting it shows it then (asked first if it has changes not saved)."
  (let* ((file (expand-file-name (+my/merge-path session) (+my/merge-toplevel session)))
         (buffer (find-buffer-visiting file)))
    (when (and buffer (buffer-modified-p buffer)
               (not (yes-or-no-p (format "%s has changes not saved: replace them? "
                                         (buffer-name buffer)))))
      (user-error "Not done"))
    (let ((coding-system-for-write (+my/merge-coding session)))
      (write-region text nil file nil 'silent))
    (when buffer
      (with-current-buffer buffer
        (revert-buffer t t t)))))

(defun +my/merge-done ()
  "Done: save the file, and stage it if no change is left; with some left,
ask first, and save them as conflict markers, not staged."
  (interactive)
  (let* ((session (+my/merge--session))
         (left (car (+my/merge--counts session))))
    (cond ((zerop left)
           (+my/merge--write session (+my/merge--result-text session))
           (let ((default-directory (+my/merge-toplevel session)))
             (+my/merge--git "add" "--" (+my/merge-path session)))
           (+my/merge--finish session)
           (message "%s resolved and staged" (+my/merge-path session)))
          ((y-or-n-p (format "%d change%s not done: save %s with conflict markers there, not staged? "
                             left (if (= left 1) " is" "s are") (+my/merge-path session)))
           (+my/merge--write session (+my/merge--markers session))
           (+my/merge--finish session)
           (message "%s saved with %d conflict%s left, not staged"
                    (+my/merge-path session) left (if (= left 1) "" "s"))))))

(defun +my/merge-abort ()
  "Abort: close, the file left as it was."
  (interactive)
  (let ((session (+my/merge--session)))
    (+my/merge--finish session)
    (message "Merge of %s aborted: the file is as it was" (+my/merge-path session))))
