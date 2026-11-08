;;; $DOOMDIR/examples/excalidraw.el -*- lexical-binding: t; -*-
;; Example: a drawing in Excalidraw (config/excalidraw.el, docs/drawings.md).
;; M-x +my/example-excalidraw writes a drawing to the temp folder (how a
;; drawing opens in Emacs: boxes, arrows, labels, a note) and opens it. Draw
;; with the mouse; Excalidraw's keys work (r a rectangle, a an arrow, t text,
;; ? lists them); Cmd+S saves it as any file; SPC m d is the dark canvas. The
;; file is deleted once it's closed.

;; ====== CODE ======

(defvar +my/example-excalidraw--seed 0)

(defun +my/example-excalidraw--element (type id x y width height &rest more)
  "An Excalidraw element (as its JSON's alist): TYPE, ID, its box, MORE
\(KEY VALUE...) over the defaults. A copy: the template's constant cells
changed in place gave every element the last one's colours."
  (let ((element (copy-tree
                  `((id . ,id) (type . ,type) (x . ,x) (y . ,y) (width . ,width) (height . ,height)
                   (angle . 0) (strokeColor . "#1e1e1e") (backgroundColor . "transparent")
                   (fillStyle . "hachure") (strokeWidth . 2) (strokeStyle . "solid")
                   (roughness . 1) (opacity . 100) (groupIds . []) (frameId . :null)
                   (roundness . ,(if (equal type "rectangle") '((type . 3)) :null))
                   (seed . ,(cl-incf +my/example-excalidraw--seed))
                   (version . 1) (versionNonce . ,+my/example-excalidraw--seed)
                   (isDeleted . :false) (boundElements . :null) (updated . 1)
                   (link . :null) (locked . :false)))))
    (while more
      (setf (alist-get (pop more) element) (pop more)))
    element))

(defun +my/example-excalidraw--box (id x y width height colour label)
  "A rectangle ID filled with COLOUR, LABEL in it: two elements."
  (let ((text-id (concat id "-label"))
        (lines (length (split-string label "\n"))))
    (list (+my/example-excalidraw--element
           "rectangle" id x y width height
           'backgroundColor colour 'boundElements (vector `((type . "text") (id . ,text-id))))
          (+my/example-excalidraw--text text-id (+ x 10) (+ y (/ (- height (* lines 25)) 2)) (- width 20) label
                                        'containerId id 'textAlign "center" 'verticalAlign "middle"))))

(defun +my/example-excalidraw--text (id x y width text &rest more)
  "A text element ID: TEXT, 20 px, Excalidraw's hand-drawn font."
  (let ((lines (length (split-string text "\n"))))
    (apply #'+my/example-excalidraw--element
           "text" id x y width (* lines 25)
           'text text 'originalText text 'fontSize 20 'fontFamily 1 'lineHeight 1.25
           'textAlign "left" 'verticalAlign "top" 'containerId :null
           more)))

(defun +my/example-excalidraw--arrow (id x y points &rest more)
  "An arrow ID from X, Y through POINTS (relative, the first (0 0))."
  (let ((xs (mapcar #'car points))
        (ys (mapcar #'cadr points)))
    (apply #'+my/example-excalidraw--element
           "arrow" id x y (- (apply #'max xs) (apply #'min xs)) (- (apply #'max ys) (apply #'min ys))
           'points (vconcat (mapcar #'vconcat points)) 'lastCommittedPoint :null
           'startBinding :null 'endBinding :null 'startArrowhead :null 'endArrowhead "arrow"
           'roundness '((type . 2))
           more)))

(defun +my/example-excalidraw--drawing ()
  "The drawing, as Excalidraw's JSON (`json-serialize': :null and :false
are JSON's null and false)."
  (setq +my/example-excalidraw--seed 0)
  (json-serialize
   `((type . "excalidraw") (version . 2) (source . "https://excalidraw.com")
     (elements
      . ,(vconcat
          (list (+my/example-excalidraw--text "title" 0 -10 520 "How a drawing opens in Emacs"
                                              'fontSize 28 'height 35))
          (+my/example-excalidraw--box "file" 0 80 250 90 "#a5d8ff" "a file\n(.excalidraw.svg)")
          (+my/example-excalidraw--box "webkit" 340 80 250 90 "#b2f2bb" "a WebKit view\nin its tab")
          (+my/example-excalidraw--box "excalidraw" 680 80 250 90 "#ffec99" "Excalidraw\n(its page)")
          (list (+my/example-excalidraw--arrow "open" 260 125 '((0 0) (70 0)))
                (+my/example-excalidraw--arrow "draw" 600 125 '((0 0) (70 0)))
                (+my/example-excalidraw--arrow "save" 805 180 '((0 0) (0 70) (-680 70) (-680 0))
                                               'strokeColor "#e03131")
                (+my/example-excalidraw--text "save-label" 200 262 460
                                              "each change exported back: Cmd+S saves it"
                                              'strokeColor "#e03131")
                (+my/example-excalidraw--element "ellipse" "you" 700 360 120 70
                                                 'backgroundColor "#ffc9c9" 'fillStyle "solid")
                (+my/example-excalidraw--text "you-label" 735 382 60 "you")
                (+my/example-excalidraw--arrow "mouse" 790 355 '((0 0) (60 -170)))
                (+my/example-excalidraw--text "mouse-label" 850 380 260
                                              "draw with the mouse,\nExcalidraw's keys work"))
          (+my/example-excalidraw--box "note" 0 340 300 100 "#e9ecef"
                                       "Markdown shows the .svg\nas any image")))
     (appState . ((viewBackgroundColor . "#ffffff") (gridSize . :null)))
     (files . ,(make-hash-table)))))

(defun +my/example-excalidraw ()
  "Example: a drawing in Excalidraw (deleted once closed). See
examples/excalidraw.el."
  (interactive)
  (let* ((dir (+my/example-folder "excalidraw"))
         (file (+my/example-write dir "how-it-opens.excalidraw" (+my/example-excalidraw--drawing))))
    ;; The drawing alone, in the one window, at its size from the start: not
    ;; `find-file', which tiling opens in a new pane (an application,
    ;; config/tiling.el) the example then had to widen, its WebKit view
    ;; resized as it loaded (at times left blank).
    (delete-other-windows)
    (set-window-buffer (selected-window) (find-file-noselect file))
    (set-buffer (window-buffer (selected-window)))
    (+my/example-delete-when-closed dir (list (current-buffer)))
    (message "Drawing example: draw with the mouse, r a rectangle, a an arrow, t text, ? the keys; SPC m d the dark canvas")
    (current-buffer)))

(defun +my/example-excalidraw-ready ()
  "Non-nil once the example's drawing is up in Excalidraw."
  (seq-some (lambda (buffer)
              (and (eq (buffer-local-value 'major-mode buffer) '+my/excalidraw-mode)
                   (buffer-local-value '+my/example--closing buffer)
                   (with-current-buffer buffer
                     (plist-get (+my/excalidraw--state) :ready))))
            (buffer-list)))

(provide 'example-excalidraw)
