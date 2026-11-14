;;; $DOOMDIR/config/treemacs/selection.el -*- lexical-binding: t; -*-
;; The selection: the file shown, highlighted. Loaded from config/treemacs.el.

;; SELECTION
;; The sidebar's selected node (its highlighted line, the arrow in the fringe)
;; is the open file, or the node you went to there (keys, a click): not the
;; line point happens to be on. Scrolling the sidebar moves point (Emacs keeps
;; it on screen) but not the selection, so the open file stays selected while
;; scrolled out of view. It's shown again (scrolled to) when the selected
;; window's buffer changes: a file opened, closed or switched to, a project
;; switched to; not when you click back into the same file, nor on Emacs's other
;; changes to its buffer list: treemacs followed on each of those (the git
;; poll's buffers, every few seconds), and scrolled the sidebar back to the file
;; as soon as you stopped scrolling. A key pressed in the sidebar acts on the
;; selection (it's scrolled back into view first).
(defvar-local +my/treemacs--selection nil
  "(PATH . MARKER): the sidebar's selected node, MARKER where it was last
drawn (see above).")

(defun +my/treemacs--sidebar-p ()
  "Non-nil in treemacs's sidebar (not in lsp-treemacs' lists, also treemacs)."
  (and (derived-mode-p 'treemacs-mode)
       (string-prefix-p treemacs-buffer-name-prefix (buffer-name))))

(defun +my/treemacs--path-at (pos)
  "The path of the node on POS's line, if there's one."
  (save-excursion
    (goto-char pos)
    (when-let* ((button (ignore-errors (treemacs-current-button))))
      (treemacs-button-get button :path))))

(defun +my/treemacs--select-here ()
  "Select the node at point (see above), its name scrolled into view."
  (when-let* ((path (+my/treemacs--path-at (point))))
    (setq +my/treemacs--selection (cons path (copy-marker (line-beginning-position))))
    (when-let* ((window (get-buffer-window (current-buffer))))
      (+my/treemacs--show-name window))))

;; SIDEWAYS
;; A node deep in the tree starts past a narrow sidebar's edge: selected, its
;; line looked blank. The sidebar scrolls sideways to the selected node, its
;; icon and name from the left edge (a column of the indentation before
;; them), if they don't fit unscrolled; back to the edge for one that does.
;; Emacs's own sideways scrolling, which follows the cursor, is off there: it
;; scrolled back to the cursor, at the line's start.
(defun +my/treemacs--show-name (window)
  "Scroll WINDOW, the sidebar, sideways to the selected node (see above)."
  (when-let* ((start (+my/treemacs--selection-start)))
    (save-excursion
      (goto-char start)
      (let ((eol (line-end-position))
            (width (lambda (end)
                     ;; Not cut at the window's edge.
                     (car (window-text-pixel-size window start end most-positive-fixnum)))))
        ;; The indentation: spaces, before the icon (a space shown as an image).
        (while (and (< (point) eol) (eq (char-after) ?\s) (not (get-text-property (point) 'display)))
          (forward-char))
        (set-window-hscroll
         window
         (if (<= (funcall width eol) (window-body-width window t))
             0
           (max 0 (1- (/ (funcall width (point))
                         (frame-char-width (window-frame window)))))))))))

(defun +my/treemacs--selection-start ()
  "Where the selected node's line starts, if it's drawn (its folders open)."
  (pcase +my/treemacs--selection
    (`(,path . ,marker)
     (if (and (marker-buffer marker) (equal (+my/treemacs--path-at marker) path))
         marker
       ;; Drawn anew since (a refresh, a folder opened above it): found again.
       (when-let* ((match (save-excursion
                            (goto-char (point-min))
                            (text-property-search-forward :path path #'equal))))
         (set-marker marker (save-excursion
                              (goto-char (prop-match-beginning match))
                              (line-beginning-position))))))))

(defun +my/treemacs--highlight-range ()
  "The line the sidebar highlights (`hl-line-range-function'): the
selection's, else point's (see above)."
  (let ((start (or (+my/treemacs--selection-start) (line-beginning-position))))
    (cons start (save-excursion (goto-char start) (line-beginning-position 2)))))

(defun +my/treemacs--scroll-command-p (command)
  "Non-nil if COMMAND only scrolls (the wheel's, C-d...): the selection stays."
  (and (symbolp command) (string-match-p "scroll" (symbol-name command))))

(defvar-local +my/treemacs--point-before nil
  "Point before the command running in the sidebar.")

(defun +my/treemacs--select-h ()
  "After a command in the sidebar: the node it went to is selected, if it went
somewhere (a key that moved, a click), not if it only scrolled (see above).
Not merely after any command: Emacs runs this hook again as its command loop
restarts (after C-g or an error), and selected the line a scroll had left
point on."
  (let ((before +my/treemacs--point-before))
    (setq +my/treemacs--point-before nil)
    (unless (+my/treemacs--scroll-command-p this-command)
      (when (or (mouse-event-p last-input-event)
                (and before (/= before (point))))
        (+my/treemacs--select-here)))))

(defun +my/treemacs--to-selection-h ()
  "Before a key's command in the sidebar: back to the selection if scrolled
away from it, which it acts on (a click acts where it clicks)."
  (unless (or (+my/treemacs--scroll-command-p this-command)
              (mouse-event-p last-input-event))
    (when-let* ((start (+my/treemacs--selection-start))
                ((/= start (line-beginning-position))))
      (goto-char start)
      (ignore-errors (treemacs--evade-image))))
  (setq +my/treemacs--point-before (point)))

(add-hook 'treemacs-mode-hook
          (defun +my/treemacs-selection-h ()
            (when (+my/treemacs--sidebar-p)
              (setq-local hl-line-range-function #'+my/treemacs--highlight-range)
              (setq-local auto-hscroll-mode nil) ; see SIDEWAYS
              ;; Before hl-line's own, which then highlights the new one.
              (add-hook 'post-command-hook #'+my/treemacs--select-h -50 t)
              (add-hook 'pre-command-hook #'+my/treemacs--to-selection-h nil t))))

;; The fringe's arrow on the selection too (it's put on point's line).
(defadvice! +my/treemacs-fringe-at-selection-a (fn &rest args)
  :around #'treemacs--move-fringe-indicator-to-point
  (if-let* (((+my/treemacs--sidebar-p))
            (overlay treemacs--fringe-indicator-overlay)
            (start (+my/treemacs--selection-start)))
      (move-overlay overlay start (1+ start))
    (apply fn args)))
