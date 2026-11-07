;;; $DOOMDIR/config/banner/row.el -*- lexical-binding: t; -*-
;; A notice's row: its icon, message, actions and ✕. Loaded from config/banner.el.

;;; A notice's row

(defun +my/banner--face (type)
  (intern (format "+my/banner-%s" (if (assq type +my/banner-types) type 'info))))

(defun +my/banner--refocus ()
  "After a click on a notice, keyboard input stays with the window it's about."
  (when-let* ((parent (frame-parent (selected-frame))))
    (select-frame-set-input-focus parent)))

(defun +my/banner--clicked-window ()
  "The window whose notice was clicked: the one under the notices' frame
selected by the click, or (a terminal's header line) the one clicked."
  (or (car (seq-find (lambda (entry) (eq (nth 1 entry) (selected-frame)))
                     +my/banner--frames))
      (let ((window (and (mouse-event-p last-input-event)
                         (posn-window (event-start last-input-event)))))
        (and (window-live-p window) window))
      (selected-window)))

(defun +my/banner--button (label function face buffer header &optional help)
  "LABEL (of FACE) calling FUNCTION in BUFFER when clicked. HEADER: it's in the
header line (a terminal's), else on a row of the notices' frame. FUNCTION runs
in the window the notice is about, the notices' frame left: run from there, an
action opening a window (e.g. Markdown's preview, beside the file) opened it
in the wrong place."
  (let ((map (make-sparse-keymap))
        (command (lambda () (interactive)
                   (let ((window (+my/banner--clicked-window)))
                     (+my/banner--refocus)
                     (when (window-live-p window)
                       (select-window window))
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer (funcall function)))))))
    (if header
        (define-key map [header-line mouse-1] command)
      (set-keymap-parent map +my/banner--row-map)
      (define-key map [mouse-1] command))
    (propertize label
                'face `(+my/banner-action ,face)
                'mouse-face 'highlight
                'pointer 'hand
                'help-echo (or help (concat "mouse-1: " (string-trim label)))
                (if header 'local-map 'keymap) map)))

(defun +my/banner--icon (type face)
  "TYPE's icon, in its colour on FACE."
  (pcase-let ((`(,_ ,icon ,colour) (or (assq type +my/banner-types)
                                       (assq 'info +my/banner-types))))
    (or (ignore-errors
          (let ((glyph (nerd-icons-codicon icon)))
            (add-face-text-property 0 (length glyph) face t glyph)
            (when (fboundp 'doom-color)
              (add-face-text-property 0 (length glyph)
                                      `(:foreground ,(doom-color colour)) nil glyph))
            glyph))
        (propertize "!" 'face face))))

(defun +my/banner--row (notice buffer &optional header more width)
  "NOTICE's row, its actions run in BUFFER: on the notices' frame, or in the
header line if HEADER (then MORE: how many other notices to mention). If the
row is WIDTH columns, the message is cut short (…) so that the actions and ✕
still fit (a narrow window, a terminal)."
  (pcase-let* ((`(,id ,text ,actions ,type) notice)
               (face (+my/banner--face type))
               (more-text (and more (> more 0) (format "    (%d more)" more)))
               (room (and width
                          (- width
                             6          ; "  " icon "  "
                             (cl-loop for action in actions
                                      sum (+ 4 (string-width (car action))))
                             (string-width (or more-text ""))
                             6)))       ; a gap, then " ✕ " 4 from the edge
               (text (if (and room (> (string-width text) room))
                         (truncate-string-to-width text (max 1 room) nil nil "…")
                       text))
               (plain (lambda (string &rest props)
                        (apply #'propertize string 'face face
                               (append props (unless header
                                               (list 'keymap +my/banner--row-map)))))))
    (concat
     (funcall plain "  ")
     (let ((icon (+my/banner--icon type face)))
       (unless header (add-text-properties 0 (length icon) (list 'keymap +my/banner--row-map) icon))
       icon)
     (funcall plain (concat "  " text))
     (mapconcat (lambda (action)
                  (concat (funcall plain "    ")
                          (+my/banner--button (car action) (cdr action) face buffer header)))
                actions "")
     (when more-text
       (propertize more-text 'face `(shadow ,face)))
     (funcall plain " " 'display '(space :align-to (- right 4)))
     (+my/banner--button " ✕ " (lambda () (+my/banner-close id)) face buffer header
                         "mouse-1: close")
     ;; To the edge: in the header line over the right margin (the stripe) and
     ;; fringe too, else they keep the header line's own colour.
     (funcall plain " " 'display (if header
                                     '(space :align-to (+ right right-margin right-fringe))
                                   '(space :align-to right))))))
