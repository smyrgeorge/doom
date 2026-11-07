;;; $DOOMDIR/config/editor/wrapped.el -*- lexical-binding: t; -*-
;; The current line and the selection across wrapped rows.
;; Loaded from config/editor.el.

;; CURRENT LINE AND SELECTION ACROSS WRAPPED ROWS
;; A long line wraps onto rows indented like it (Doom's word wrap: e.g. two
;; spaces in a Markdown table), and the current line's highlight, and the
;; selection's, left that indentation out: Emacs draws a line's wrap prefix
;; (and line prefix) without the faces of the overlays on it, so a strip of
;; plain background stayed at the start of each continuation row. hl-line's
;; overlay now carries copies of the line's prefixes in its face (an overlay's
;; prefix wins over the text's); the selection, which spans lines with their
;; own prefixes, gets a small overlay per line on screen.
(defun +my/hl-line--prefix (prefix face)
  "PREFIX (a `wrap-prefix' or `line-prefix' value) drawn in FACE too."
  (cond ((null prefix) nil)
        ((stringp prefix)
         (let ((copy (copy-sequence prefix)))
           (add-face-text-property 0 (length copy) face nil copy)
           copy))
        ;; A display spec, e.g. (space :width 4).
        (t (propertize " " 'display prefix 'face face))))

(defun +my/hl-line-prefixes (overlay)
  "Give hl-line's OVERLAY its line's prefixes, in its face (see above)."
  (when (and (overlayp overlay) (overlay-buffer overlay))
    (with-current-buffer (overlay-buffer overlay)
      (let* ((pos (overlay-start overlay))
             ;; Only where the highlight is the whole line, across the window:
             ;; a mode that highlights part of it (Doom's dashboard: the menu
             ;; item, its line centred by a prefix) keeps that look.
             (whole (= (overlay-end overlay)
                       (save-excursion (goto-char pos)
                                       (line-beginning-position 2))))
             (face (overlay-get overlay 'face))
             (wrap (and whole (or (get-text-property pos 'wrap-prefix)
                                  wrap-prefix)))
             (line (and whole (or (get-text-property pos 'line-prefix)
                                  line-prefix)))
             (key (overlay-get overlay '+my/prefixes)))
        ;; Only when the line, its prefixes or the face changed (this runs
        ;; before every redisplay).
        (unless (and key (eq (nth 0 key) wrap) (eq (nth 1 key) line)
                     (equal (nth 2 key) face) (eql (nth 3 key) pos))
          (overlay-put overlay '+my/prefixes (list wrap line face pos))
          (overlay-put overlay 'wrap-prefix
                       (+my/hl-line--prefix wrap face))
          (overlay-put overlay 'line-prefix
                       (+my/hl-line--prefix line face)))))))

;; `global-hl-line-sticky-flag' `window' (Doom's): an overlay per window, kept
;; in a window parameter; otherwise one moved by `hl-line-move'.
(defadvice! +my/hl-line-window-prefixes-a (window)
  :after #'global-hl-line-window-redisplay
  (+my/hl-line-prefixes (window-parameter window 'hl-line-overlay)))

(defadvice! +my/hl-line-move-prefixes-a (overlay)
  :after #'hl-line-move
  (+my/hl-line-prefixes overlay))

(defun +my/region-prefixes (window)
  "Give the selected lines on WINDOW's screen their prefixes in the
selection's face, each over its part of the selection (see above)."
  (let* ((region (window-parameter window 'internal-region-overlay))
         (buffer (window-buffer window))
         (active (and (overlayp region) (eq (overlay-buffer region) buffer)
                      (< (overlay-start region) (overlay-end region))))
         ;; Redone only when the selection, the scroll position or the text
         ;; (word wrap adds prefixes as lines are first shown) changed.
         (key (and active
                   (list (overlay-start region) (overlay-end region)
                         (overlay-get region 'face) (window-start window)
                         (window-body-height window)
                         (buffer-modified-tick buffer)))))
    (unless (equal key (window-parameter window '+my/region-prefixes-key))
      (set-window-parameter window '+my/region-prefixes-key key)
      (let ((spare (window-parameter window '+my/region-prefixes))
            (used nil))
        (when active
          (with-current-buffer buffer
            (save-excursion
              (let* ((face (overlay-get region 'face))
                     (beg (overlay-start region))
                     ;; No further than the screen: a line takes a row at
                     ;; least.
                     (end (min (overlay-end region)
                               (progn (goto-char (window-start window))
                                      (forward-line (window-body-height window))
                                      (point)))))
                (goto-char (max beg (window-start window)))
                (forward-line 0)
                (while (< (point) end)
                  (let* ((bol (point))
                         (wrap (or (get-text-property bol 'wrap-prefix)
                                   wrap-prefix))
                         (line (or (get-text-property bol 'line-prefix)
                                   line-prefix)))
                    (when (or wrap line)
                      (let ((ov (or (pop spare) (make-overlay 1 1))))
                        (move-overlay ov (max bol beg)
                                      (min (line-beginning-position 2)
                                           (overlay-end region))
                                      buffer)
                        (overlay-put ov 'window window)
                        ;; Above hl-line's, which carries its own copies.
                        (overlay-put ov 'priority '(nil . 110))
                        (overlay-put ov 'wrap-prefix
                                     (+my/hl-line--prefix wrap face))
                        (overlay-put ov 'line-prefix
                                     (+my/hl-line--prefix line face))
                        (push ov used))))
                  (forward-line 1))))))
        (mapc #'delete-overlay spare)
        (set-window-parameter window '+my/region-prefixes used)))))

(defadvice! +my/region-prefixes-a (window)
  :after #'redisplay--update-region-highlight
  (when (window-live-p window)
    (+my/region-prefixes window)))
