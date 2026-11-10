;;; $DOOMDIR/config/beads/place.el -*- lexical-binding: t; -*-
;; An issue list keeps its place when it's refreshed. Loaded from
;; config/beads.el.

;; THE PLACE KEPT
;; beads.el redraws a list and puts back where it was by the buffer's
;; positions, and the selected window's: a refresh (the timer's, after
;; Claude's bd commands, gr) scrolled the list when an issue came or went
;; above what's in view, to another pane's place when it wasn't the selected
;; window, and only one window showing it got its place back. Each window
;; showing the list keeps it now by its issues: the one at its top, the one
;; its cursor is on (else the same lines), restored after the redraw.
(defun +my/beads--place (window)
  "WINDOW's place in its list: (WINDOW TOP-ID TOP-LINE ID LINE COLUMN), the
issues (and lines) at its top and at its cursor."
  ;; Both read first: the selected window's point is the buffer's, moved here.
  (let ((start (window-start window))
        (point (window-point window)))
    (save-excursion
      (goto-char start)
      (let ((top-id (tabulated-list-get-id))
            (top-line (line-number-at-pos)))
        (goto-char point)
        (list window top-id top-line (tabulated-list-get-id) (line-number-at-pos) (current-column))))))

(defun +my/beads--line-of (id line)
  "Where ID's row starts, else LINE's (the last line's at most)."
  (save-excursion
    (goto-char (point-min))
    (let ((found nil))
      (when id
        (while (and (not found) (not (eobp)))
          (if (equal (tabulated-list-get-id) id)
              (setq found (point))
            (forward-line 1))))
      (or found
          (progn (goto-char (point-min))
                 (forward-line (1- (max 1 line)))
                 (when (and (eobp) (not (bobp)) (bolp))
                   (forward-line -1))
                 (line-beginning-position))))))

(defun +my/beads--restore-place (place)
  "PLACE (see `+my/beads--place') back in its window, if it still shows
this list."
  (pcase-let ((`(,window ,top-id ,top-line ,id ,line ,column) place))
    (when (and (window-live-p window) (eq (window-buffer window) (current-buffer)))
      (let ((point (save-excursion
                     (goto-char (+my/beads--line-of id line))
                     (move-to-column column)
                     (point))))
        (set-window-start window (+my/beads--line-of top-id top-line))
        (set-window-point window point)
        (when (eq window (selected-window))
          (goto-char point))))))

(defun +my/beads-keep-place-a (fn &rest args)
  "`beads-list-refresh': each window showing the list keeps its place (see
above)."
  (let ((places (mapcar #'+my/beads--place (get-buffer-window-list (current-buffer) nil t))))
    (prog1 (apply fn args)
      (mapc #'+my/beads--restore-place places))))

(after! beads-list
  (advice-add 'beads-list-refresh :around #'+my/beads-keep-place-a))
