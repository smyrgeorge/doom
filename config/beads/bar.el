;;; $DOOMDIR/config/beads/bar.el -*- lexical-binding: t; -*-
;; The issue list's bar: its counts, short in a narrow pane. Loaded from
;; config/beads.el.

;; THE BAR
;; beads.el's bar under the list says the project's counts in words, after
;; the list's name (" *Beads: api*   8 total | 6 open | 1 in progress | 1
;; blocked | 5 ready", 84 columns): a narrower pane cut them, at 25 columns
;; all of them. Where it doesn't fit, its counts come first, as the list's
;; icons in their colours (○5 ◔1 ⊘1 ✓1: ready, in progress, blocked,
;; closed), then the list's name.
(defvar-local +my/beads--stats nil
  "The list's counts (bd stats), for its bar.")

(defconst +my/beads--bar-counts
  '((ready_issues . "ready") (in_progress_issues . "in_progress")
    (blocked_issues . "blocked") (closed_issues . "closed"))
  "The counts the short bar shows: (COUNT . STATUS), STATUS's icon before it
\(`+my/beads--statuses-look').")

(defun +my/beads--short-counts (stats)
  "STATS (bd stats) short: each count after its status's icon, in its colour."
  (mapconcat (lambda (count)
               (let ((look (assoc (cdr count) +my/beads--statuses-look)))
                 (propertize (format "%s%d" (nth 1 look) (alist-get (car count) stats 0))
                             'face (nth 2 look))))
             +my/beads--bar-counts " "))

(defun +my/beads--bar (&optional width)
  "The list's bar for a window WIDTH columns wide (default: the one it's drawn
in): see above."
  (let* ((name (propertize (string-replace "%" "%%" (buffer-name)) 'face 'mode-line-buffer-id))
         (full (concat " " name "  " (beads-list--format-header-line +my/beads--stats))))
    (if (<= (string-width full) (or width (window-total-width)))
        full
      (concat " " (+my/beads--short-counts +my/beads--stats) "  " name))))

(defun +my/beads-update-bar ()
  "`beads-list--update-mode-line': the list's bar (see above), its counts
asked of bd; beads.el's mode line without them."
  (if beads-list-show-header-stats
      (condition-case nil
          (setq +my/beads--stats (beads-client-stats)
                mode-line-format '((:eval (+my/beads--bar))))
        (beads-client-error
         (setq mode-line-format (default-value 'mode-line-format))))
    (setq mode-line-format (default-value 'mode-line-format))))

(after! beads-list
  (advice-add 'beads-list--update-mode-line :override #'+my/beads-update-bar))
