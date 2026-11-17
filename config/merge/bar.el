;;; $DOOMDIR/config/merge/bar.el -*- lexical-binding: t; -*-
;; The bar above the panes. Loaded from config/merge.el.

;; THE BAR
;; Its labels: the longest that fit its window, down to Done and Abort alone
;; (a terminal's 80 columns, a frame split, a laptop). Its wand: the margins'
;; icon in the GUI (an emoji's row is taller than the bar's one line: its
;; buttons were cut at the bottom), ✨ in a terminal.
(defconst +my/merge--bar-levels 5
  "The bar's shortest labels' level (see `+my/merge--bar-text').")

(defun +my/merge--bar-button (label command help)
  "A button of the bar: LABEL, its own faces kept (the wand's icon's font)."
  (let ((start (point)))
    (insert label)
    (make-text-button start (point) 'action (lambda (_) (+my/merge--from-bar command))
                      'follow-link t 'help-echo help 'pointer 'hand)
    (add-face-text-property start (point) '+my/merge-button t)))

(defun +my/merge--from-bar (command)
  "A button of the bar: COMMAND, from the Result's pane."
  (let ((session +my/merge--session))
    (when-let* ((window (get-buffer-window (+my/merge-result session))))
      (select-window window))
    (call-interactively command)))

(defun +my/merge--bar-text (session level)
  "SESSION's bar's content at LEVEL: 0 its long labels; 1 short ones; 2 the
wand without words; 3 what's left without the conflicts; 4 without Left and
Right (SPC m L / R); 5 (`+my/merge--bar-levels') Done and Abort only."
  (let* ((counts (+my/merge--counts session))
         (left (car counts))
         (conflicts (cdr counts))
         (wand (+my/merge--icon "nf-cod-wand" "✨"))
         (gap (if (< level 2) "   " "  ")))
    (insert " ")
    (when (< level 4)
      (+my/merge--bar-button (if (zerop level) "Accept Left" "Left") #'+my/merge-accept-left
                             "Accept Left: Yours for every change not done yet")
      (insert "  ")
      (+my/merge--bar-button (if (zerop level) "Accept Right" "Right") #'+my/merge-accept-right
                             "Accept Right: Theirs for every change not done yet")
      (insert "  "))
    (when (< level 5)
      (+my/merge--bar-button (pcase level
                               (0 (concat wand " Apply non-conflicting"))
                               (1 (concat wand " Non-conflicting"))
                               (_ wand))
                             #'+my/merge-apply-non-conflicting
                             "Apply non-conflicting: every change only one side made, not done yet")
      (insert gap
              (propertize
               (cond ((zerop left) (if (zerop level) "All changes done" "All done"))
                     ((< level 3)
                      (format "%d%s left, %d conflict%s"
                              left
                              (cond ((> level 0) "") ((= left 1) " change") (t " changes"))
                              conflicts (if (= conflicts 1) "" "s")))
                     (t (format "%d left" left)))
               'face (if (zerop left) 'success 'warning))
              gap))
    (+my/merge--bar-button "Done" #'+my/merge-done
                           "Save the file, and stage it if no change is left")
    (insert "  ")
    (+my/merge--bar-button "Abort" #'+my/merge-abort "Close, the file left as it was")
    ;; Not a button last: Emacs drew its highlight on to the window's edge.
    (insert " ")))

(defun +my/merge--render-bar (session &optional width)
  "Show SESSION's bar: its buttons and what's left, with the longest labels
that fit in WIDTH columns (default: its window's width, measured as drawn:
an icon is wider than a column)."
  (when-let* ((bar (and session (+my/merge-bar session)))
              ((buffer-live-p bar)))
    (with-current-buffer bar
      (let* ((inhibit-read-only t)
             (window (get-buffer-window bar t))
             (fits (cond (width
                          (lambda () (<= (string-width (buffer-string)) width)))
                         (window
                          (let ((room (window-body-width window t)))
                            (lambda () (<= (string-pixel-width (buffer-string) bar) room))))
                         (t (let ((room (frame-width)))
                              (lambda () (<= (string-width (buffer-string)) room))))))
             (level 0))
        (erase-buffer)
        (+my/merge--bar-text session level)
        (while (and (< level +my/merge--bar-levels) (not (funcall fits)))
          (cl-incf level)
          (erase-buffer)
          (+my/merge--bar-text session level))
        (goto-char (point-min))))))

(defun +my/merge--bar-resized-h (window)
  "The bar's window resized: its labels to fit."
  (+my/merge--render-bar (buffer-local-value '+my/merge--session (window-buffer window))))

(define-derived-mode +my/merge-bar-mode special-mode "Merge"
  "The bar above a merge's panes (see config/merge.el)."
  (setq-local mode-line-format nil
              header-line-format nil
              cursor-type nil
              ;; Too long (a window narrower than Done and Abort): cut, not
              ;; wrapped onto a second line nobody sees.
              truncate-lines t
              window-size-fixed 'height))
