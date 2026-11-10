;;; $DOOMDIR/config/treemacs/sticky.el -*- lexical-binding: t; -*-
;; The project's title stays at the sidebar's top while its files scroll.
;; Loaded from config/treemacs.el.
;;
;; The sidebar's header line shows the root line ("doom  main ↑2": name,
;; branch, ↑↓) of the project whose files are at the top, as the tree shows
;; it; with several projects, the one in view. Always there (while
;; `+my/treemacs-sticky-title' is on), at the top too: one that came only once
;; the root line was scrolled out flickered (it went while scrolling, and
;; came back when it stopped), and moved the tree down a line as it came. Its
;; :eval reads the title from the tree each time it's drawn: a new branch,
;; ↑↓, another project in view show at once. A click on it goes to the
;; project's line.
;;
;; As the tree: the header line starts at the window's edge, the tree after
;; the left fringe (and margin), so the title starts after a space as wide;
;; and it has the sidebar's background (solaire's, darker than the header
;; line's), no box or lines.

(defun +my/treemacs--project-at (start)
  "Where the root line is of the project whose nodes are at START's line (that
root line, or above it), in the current treemacs buffer; nil above every
project."
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
    best))

(defvar +my/treemacs-sticky-map
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1] #'+my/treemacs-sticky-goto)
    map)
  "Keys on the sticky title: a click goes to the project's line.")

(defvar-local +my/treemacs--sticky-last nil
  "The title last shown: kept while the tree has none to show (drawn anew).")

(defun +my/treemacs--sticky-indent (window)
  "A space as wide as WINDOW's left fringe and margin (see above)."
  (propertize " " 'display
              `(space :width (,(+ (or (car (window-fringes window)) 0)
                                  (* (or (car (window-margins window)) 0)
                                     (frame-char-width (window-frame window))))))))

(defun +my/treemacs--sticky-title ()
  "The sticky header line: the root line of the project at the window's top,
as the tree shows it (see above)."
  (let* ((window (selected-window))
         (bol (ignore-errors (+my/treemacs--project-at (window-start window)))))
    (when bol
      (setq +my/treemacs--sticky-last
            (propertize
             (string-replace "%" "%%" (buffer-substring bol (save-excursion
                                                              (goto-char bol)
                                                              (line-end-position))))
             'mouse-face 'highlight)))
    (propertize (concat (+my/treemacs--sticky-indent window) (or +my/treemacs--sticky-last ""))
                'local-map +my/treemacs-sticky-map
                'help-echo "mouse-1: go to the project")))

(defun +my/treemacs-sticky-goto (event)
  "Go to the line of the project whose title was clicked (EVENT)."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (select-window window)
      (when-let* ((bol (+my/treemacs--project-at (window-start window))))
        (goto-char bol)
        (treemacs--evade-image)
        (set-window-start window bol)))))

(defun +my/treemacs--background ()
  "The sidebar's background as shown: its default face's remapping's (solaire's),
else the default face's."
  (or (seq-some (lambda (spec)
                  (cond ((facep spec) (face-background spec nil nil))
                        ((and (consp spec) (keywordp (car spec))) (plist-get spec :background))))
                (let ((remap (alist-get 'default face-remapping-alist)))
                  (if (listp remap) remap (list remap))))
      (face-background 'default nil t)))

(defvar-local +my/treemacs--sticky-remaps nil
  "The header line's faces remapped in the sidebar (their cookies).")

(defun +my/treemacs--sticky-faces ()
  "The header line in the sidebar's background, without box or lines."
  (mapc #'face-remap-remove-relative +my/treemacs--sticky-remaps)
  (setq +my/treemacs--sticky-remaps
        (when +my/treemacs-sticky-title
          (let ((spec (list :background (+my/treemacs--background)
                            :box nil :overline nil :underline nil)))
            (mapcar (lambda (face) (face-remap-add-relative face spec))
                    '(header-line header-line-active header-line-inactive))))))

(defun +my/treemacs-sticky-h ()
  "The sticky title in the sidebar (not in lsp-treemacs' lists), if on."
  (when (+my/treemacs--sidebar-p)
    (setq-local header-line-format
                (and +my/treemacs-sticky-title '(:eval (+my/treemacs--sticky-title))))
    (+my/treemacs--sticky-faces)))

;; Late: after solaire's remapping of the sidebar's faces, whose background
;; it takes.
(add-hook 'treemacs-mode-hook #'+my/treemacs-sticky-h 90)

(defun +my/treemacs-sticky-all-h (&rest _)
  "The sticky title in every sidebar again (a new theme: its background)."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'treemacs-mode)
        (+my/treemacs-sticky-h)))))

(add-hook 'doom-load-theme-hook #'+my/treemacs-sticky-all-h 90)

;; Treemacs' buffers made before this was loaded (reloading the config); an
;; earlier version's window parameter gone.
(when (featurep 'treemacs)
  (+my/treemacs-sticky-all-h)
  (dolist (window (window-list-1 nil 'nomini t))
    (when (and (window-parameter window 'header-line-format)
               (with-current-buffer (window-buffer window) (derived-mode-p 'treemacs-mode)))
      (set-window-parameter window 'header-line-format nil))))
