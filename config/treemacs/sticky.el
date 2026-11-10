;;; $DOOMDIR/config/treemacs/sticky.el -*- lexical-binding: t; -*-
;; The project's title stays at the sidebar's top while its files scroll.
;; Loaded from config/treemacs.el.
;;
;; Once its root line ("doom  main ↑2": name, branch, ↑↓) is scrolled out of
;; view, the window's header line shows it, as that line shows it (scrolled
;; back to the top: no header line, the title isn't shown twice). Several
;; projects: the one whose files are at the top. A click on it goes to the
;; project's line.
;;
;; A header line can't come and go through `header-line-format' alone (an
;; :eval giving nil still leaves an empty line): the window's own
;; `header-line-format' parameter is set while a root line is scrolled out
;; (checked when the window's start changes, and after a refresh), and its
;; :eval reads the title from the tree each time it's drawn (a new branch,
;; ↑↓ show at once).

(defun +my/treemacs--root-above (start)
  "Where the root line is of the project whose nodes are at START's line, in
the current treemacs buffer, if that line is below it (scrolled out above
a window starting at START); nil when START's line is a project's root line,
or above every project."
  (let ((top (save-excursion (goto-char start) (line-beginning-position)))
        (best nil))
    (dolist (project (ignore-errors
                       (treemacs-workspace->projects (treemacs-current-workspace))))
      (when-let* ((pos (ignore-errors (treemacs-project->position project)))
                  ((or (integerp pos)
                       (and (markerp pos) (eq (marker-buffer pos) (current-buffer)))))
                  (bol (save-excursion (goto-char pos) (line-beginning-position)))
                  ((<= bol top))
                  ((or (null best) (> bol best))))
        (setq best bol)))
    (and best (< best top) best)))

(defvar +my/treemacs-sticky-map
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1] #'+my/treemacs-sticky-goto)
    map)
  "Keys on the sticky title: a click goes to the project's line.")

(defun +my/treemacs--sticky-title ()
  "The sticky header line's text: the root line above the window's top, as
the tree shows it (\"\" when there's none any more: the header line is
taken away right after)."
  (if-let* ((bol (ignore-errors (+my/treemacs--root-above (window-start)))))
      (propertize
       (string-replace "%" "%%" (buffer-substring bol (save-excursion
                                                        (goto-char bol)
                                                        (line-end-position))))
       'local-map +my/treemacs-sticky-map
       'mouse-face 'highlight
       'help-echo "mouse-1: go to the project")
    (let ((window (selected-window)))
      (run-at-time 0 nil #'+my/treemacs--sticky-update window))
    ""))

(defun +my/treemacs--sticky-update (window &optional start)
  "Show the sticky title in treemacs' WINDOW (starting at START, default its
start) if a project's root line is scrolled out above; else no header line."
  (when (and (window-live-p window)
             (with-current-buffer (window-buffer window)
               (derived-mode-p 'treemacs-mode)))
    (let ((wanted (with-current-buffer (window-buffer window)
                    (and (ignore-errors
                           (+my/treemacs--root-above (or start (window-start window))))
                         '(:eval (+my/treemacs--sticky-title))))))
      (unless (equal wanted (window-parameter window 'header-line-format))
        (set-window-parameter window 'header-line-format wanted)
        (force-mode-line-update)))))

(defun +my/treemacs-sticky-goto (event)
  "Go to the line of the project whose title was clicked (EVENT)."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (with-selected-window window
        (when-let* ((bol (+my/treemacs--root-above (window-start))))
          (goto-char bol)
          (treemacs--evade-image)
          (set-window-start window bol)
          (+my/treemacs--sticky-update window bol)))
      (select-window window))))

(defun +my/treemacs-sticky-h ()
  "Check the sticky title whenever the sidebar's start changes."
  (add-hook 'window-scroll-functions #'+my/treemacs--sticky-update nil t))

(add-hook 'treemacs-mode-hook #'+my/treemacs-sticky-h)

(defun +my/treemacs-sticky-after-refresh-h (&rest _)
  "A refresh redraws the tree (maybe the window's start isn't moved): check."
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (+my/treemacs--sticky-update window)))

(add-hook 'treemacs-post-refresh-hook #'+my/treemacs-sticky-after-refresh-h)

;; Treemacs' buffers made before this was loaded (reloading the config).
(when (featurep 'treemacs)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'treemacs-mode)
        (+my/treemacs-sticky-h)
        (dolist (window (get-buffer-window-list buffer nil t))
          (+my/treemacs--sticky-update window))))))
