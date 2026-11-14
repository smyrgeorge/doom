;;; $DOOMDIR/config/beads/preview.el -*- lexical-binding: t; -*-
;; The issue list's preview (P): beside it, in the background, its own.
;; Loaded from config/beads.el.

;; THE PREVIEW
;; beads.el showed the issue under the cursor (P) in a window on the
;; frame's right edge, 40% of its width: it squeezed the list (in a 40
;; column pane, to 21: no titles left) and the panes between them, waited
;; for bd on each row (half a second a j), stayed once the list was gone, and
;; was one for every project. Here each list has its own, beside it: in its
;; pane if that's wide enough to keep the list readable, else taken from the
;; pane next to it; asked of bd in the background (a row moved over before
;; its answer came: dropped); closed with its list (P again, q, the list
;; killed).
(defconst +my/beads--list-min-width 60
  "Columns a list keeps when its preview is taken from its own pane.")

(defconst +my/beads--preview-min-width 40
  "Columns a preview takes, at least, from its list's pane.")

(defvar-local +my/beads--preview nil
  "This list's preview: its buffer.")

(defun +my/beads--preview-buffer ()
  "This list's preview buffer, made if need be (in its project's folder)."
  (if (buffer-live-p +my/beads--preview)
      +my/beads--preview
    (let ((dir default-directory)
          (buffer (generate-new-buffer
                   (replace-regexp-in-string "\\`\\*Beads: " "*Beads Preview: " (buffer-name)))))
      (with-current-buffer buffer
        (setq default-directory dir))
      (setq +my/beads--preview buffer))))

(defun +my/beads--side-pane (window)
  "The pane next to WINDOW, on its right, else its left: (PANE . SIDE), SIDE
the side of PANE WINDOW is on; or nil."
  (seq-some (lambda (direction)
              (when-let* ((pane (window-in-direction direction window))
                          ((not (window-parameter pane 'window-side)))
                          ((not (window-minibuffer-p pane))))
                (cons pane (if (eq direction 'right) 'left 'right))))
            '(right left)))

(defun +my/beads--preview-window (list-window buffer)
  "A window showing BUFFER (a preview) beside LIST-WINDOW (see above): the one
showing it already, else a new one."
  (or (get-buffer-window buffer)
      (let* ((width (window-total-width list-window))
             (side (+my/beads--side-pane list-window))
             (window
              (or (and (>= width (+ +my/beads--list-min-width +my/beads--preview-min-width))
                       (ignore-errors
                         (split-window list-window
                                       (- (max +my/beads--preview-min-width (/ (* width 2) 5)))
                                       'right)))
                  (and side
                       (ignore-errors
                         (split-window (car side) (- (/ (window-total-width (car side)) 2)) (cdr side))))
                  (split-window list-window nil 'right))))
        (set-window-buffer window buffer)
        (set-window-prev-buffers window nil)
        (set-window-dedicated-p window t)
        window)))

(defun +my/beads--preview-draw (list preview answer)
  "ANSWER (bd show's, fetched) drawn in PREVIEW, LIST's preview, shown beside
LIST's window; not if LIST no longer previews."
  (when (and (buffer-live-p list) (buffer-live-p preview)
             (buffer-local-value 'beads-preview-mode list))
    (let* ((issue (+my/beads--parent-ids-a (+my/beads--one-issue-a answer)))
           (id (alist-get 'id issue)))
      (with-current-buffer preview
        (setq beads-detail--current-issue-id id
              beads-detail--current-issue issue)
        (if beads-detail-use-vui
            (beads-detail--render-vui preview issue)
          (unless (eq major-mode 'beads-detail-mode)
            (beads-detail-mode))
          (let ((inhibit-read-only t))
            (erase-buffer)
            (beads-detail--render issue)
            (goto-char (point-min)))))
      (when-let* ((window (get-buffer-window list)))
        (+my/beads--preview-window window preview)))))

(defun +my/beads--preview-issue (list issue)
  "ISSUE (the one at the cursor in LIST) previewed: asked of bd in the
background, drawn once its answer came (see above)."
  (when (and (buffer-live-p list) issue)
    (with-current-buffer list
      (when-let* ((beads-preview-mode)
                  (id (alist-get 'id issue))
                  ((not (equal id beads-preview--current-issue-id))))
        (setq beads-preview--current-issue-id id)
        (let ((preview (+my/beads--preview-buffer)))
          (+my/beads--cancel preview)
          (+my/beads--fetch preview `(("show" (id . ,id)))
                            (lambda (answers)
                              (+my/beads--preview-draw list preview (cdr (assoc "show" answers))))))))))

(defun +my/beads-preview-timer-a (issue)
  "`beads-preview--start-timer': ISSUE previewed a moment after the cursor
stops (`beads-preview-delay'), from this list."
  (beads-preview--cancel-timer)
  (setq beads-preview--timer
        (run-with-idle-timer beads-preview-delay nil #'+my/beads--preview-issue (current-buffer) issue)))

(defun +my/beads-preview-close-a ()
  "`beads-preview--cleanup': this list's preview gone, its window with it."
  (beads-preview--cancel-timer)
  (setq beads-preview--current-issue-id nil)
  (when (buffer-live-p +my/beads--preview)
    (dolist (window (get-buffer-window-list +my/beads--preview nil t))
      (when (window-deletable-p window)
        (delete-window window)))
    (kill-buffer +my/beads--preview))
  (setq +my/beads--preview nil))

(defun +my/beads--preview-h ()
  "A list: its preview closed when it's killed."
  (add-hook 'kill-buffer-hook #'+my/beads-preview-close-a nil t))

(add-hook 'beads-list-mode-hook #'+my/beads--preview-h)

(after! beads-preview
  (advice-add 'beads-preview--start-timer :override #'+my/beads-preview-timer-a)
  (advice-add 'beads-preview--cleanup :override #'+my/beads-preview-close-a))
