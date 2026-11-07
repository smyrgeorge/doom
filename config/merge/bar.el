;;; $DOOMDIR/config/merge/bar.el -*- lexical-binding: t; -*-
;; The bar above the panes. Loaded from config/merge.el.

;; THE BAR
(defun +my/merge--bar-button (label command help)
  (insert-text-button label 'action (lambda (_) (+my/merge--from-bar command))
                      'face '+my/merge-button 'follow-link t 'help-echo help
                      'pointer 'hand))

(defun +my/merge--from-bar (command)
  "A button of the bar: COMMAND, from the Result's pane."
  (let ((session +my/merge--session))
    (when-let* ((window (get-buffer-window (+my/merge-result session))))
      (select-window window))
    (call-interactively command)))

(defun +my/merge--bar-text (session short)
  "SESSION's bar's content; SHORT: with short labels (a narrow frame, a
terminal's 80 columns)."
  (let ((counts (+my/merge--counts session)))
    (insert " ")
    (+my/merge--bar-button (if short "Left" "Accept Left") #'+my/merge-accept-left
                           "Accept Left: Yours for every change not done yet")
    (insert "  ")
    (+my/merge--bar-button (if short "Right" "Accept Right") #'+my/merge-accept-right
                           "Accept Right: Theirs for every change not done yet")
    (insert "  ")
    (+my/merge--bar-button (if short "✨ Non-conflicting" "✨ Apply non-conflicting")
                           #'+my/merge-apply-non-conflicting
                           "Apply every change only one side made, not done yet")
    (insert "   "
            (propertize
             (cond ((zerop (car counts)) (if short "All done" "All changes done"))
                   (t (format "%d%s left, %d conflict%s"
                              (car counts)
                              (cond (short "") ((= (car counts) 1) " change") (t " changes"))
                              (cdr counts) (if (= (cdr counts) 1) "" "s"))))
             'face (if (zerop (car counts)) 'success 'warning))
            "   ")
    (+my/merge--bar-button "Done" #'+my/merge-done
                           "Save the file, and stage it if no change is left")
    (insert "  ")
    (+my/merge--bar-button "Abort" #'+my/merge-abort "Close, the file left as it was")
    ;; Not a button last: Emacs drew its highlight on to the window's edge.
    (insert " ")))

(defun +my/merge--render-bar (session &optional width)
  "Show SESSION's bar: its buttons and what's left, with short labels if the
long ones don't fit in WIDTH columns (default: its window's)."
  (when-let* ((bar (and session (+my/merge-bar session)))
              ((buffer-live-p bar)))
    (with-current-buffer bar
      (let ((inhibit-read-only t)
            (width (or width
                       (and (get-buffer-window bar t) (window-max-chars-per-line (get-buffer-window bar t)))
                       (frame-width))))
        (erase-buffer)
        (+my/merge--bar-text session nil)
        (when (> (string-width (buffer-string)) width)
          (erase-buffer)
          (+my/merge--bar-text session t))
        (goto-char (point-min))))))

(defun +my/merge--bar-resized-h (window)
  "The bar's window resized: its labels to fit."
  (+my/merge--render-bar (buffer-local-value '+my/merge--session (window-buffer window))))

(define-derived-mode +my/merge-bar-mode special-mode "Merge"
  "The bar above a merge's panes (see config/merge.el)."
  (setq-local mode-line-format nil
              header-line-format nil
              cursor-type nil
              window-size-fixed 'height))
