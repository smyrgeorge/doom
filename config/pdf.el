;;; $DOOMDIR/config/pdf.el -*- lexical-binding: t; -*-
;; PDF zoom like macOS apps. Loaded from config.el.

;; ====== VARIABLES ======

;; PDF ZOOM
;; In PDFs (pdf-tools): Cmd+= (or Cmd++) zooms in, Cmd+- out, Cmd+0 shows the
;; actual size (as in Preview; P fits the page again); Cmd+scroll zooms in (up)
;; or out (down), a step per wheel notch (trackpads: per few lines' worth of
;; scrolling). Elsewhere Cmd+= / Cmd+- still change the font size. pdf-tools'
;; own keys stay: + / - / 0, W / H / P.
(defvar +my/pdf-wheel-zoom-step 1.1
  "How much each wheel step of Cmd+scroll zooms (a factor).")

(defvar +my/pdf-wheel-zoom-pixels 40
  "How many pixels of scrolling make a zoom step (a mouse wheel notch: ~50).")

;; ====== KEY BINDINGS ======

(map! :after pdf-view
      :map pdf-view-mode-map
      "s-="  #'pdf-view-enlarge
      "s-+"  #'pdf-view-enlarge
      "s--"  #'pdf-view-shrink
      "s-0"  #'pdf-view-scale-reset
      [s-wheel-up]          #'+my/pdf-wheel-zoom
      [s-wheel-down]        #'+my/pdf-wheel-zoom
      [s-double-wheel-up]   #'+my/pdf-wheel-zoom
      [s-double-wheel-down] #'+my/pdf-wheel-zoom
      [s-triple-wheel-up]   #'+my/pdf-wheel-zoom
      [s-triple-wheel-down] #'+my/pdf-wheel-zoom)

;; ====== CODE ======

(defvar +my/pdf--wheel-pixels 0 "Scrolling not yet worth a zoom step.")

(defun +my/pdf-wheel-zoom (event)
  "Cmd+scroll: zoom the PDF under the mouse in (scrolling up) or out."
  (interactive "e")
  (let* ((window (posn-window (event-start event)))
         (up (memq (event-basic-type event) '(wheel-up mouse-4)))
         (pixels (if (consp (nth 4 event))
                     (abs (cdr (nth 4 event)))
                   +my/pdf-wheel-zoom-pixels)) ; no pixel data: a step
         (signed (if up pixels (- pixels))))
    ;; Changing direction drops what was gathered the other way.
    (when (< (* signed +my/pdf--wheel-pixels) 0)
      (setq +my/pdf--wheel-pixels 0))
    (setq +my/pdf--wheel-pixels (+ +my/pdf--wheel-pixels signed))
    (when (window-live-p window)
      (with-selected-window window
        (when (derived-mode-p 'pdf-view-mode)
          (while (>= (abs +my/pdf--wheel-pixels) +my/pdf-wheel-zoom-pixels)
            (if (> +my/pdf--wheel-pixels 0)
                (progn (pdf-view-enlarge +my/pdf-wheel-zoom-step)
                       (setq +my/pdf--wheel-pixels
                             (- +my/pdf--wheel-pixels +my/pdf-wheel-zoom-pixels)))
              (pdf-view-shrink +my/pdf-wheel-zoom-step)
              (setq +my/pdf--wheel-pixels
                    (+ +my/pdf--wheel-pixels +my/pdf-wheel-zoom-pixels)))))))))
