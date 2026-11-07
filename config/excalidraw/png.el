;;; $DOOMDIR/config/excalidraw/png.el -*- lexical-binding: t; -*-
;; A drawing as a PNG (see config/excalidraw.el). Loaded from
;; config/excalidraw.el.

;; The page makes it in the background (excalidraw.js's png()): Emacs asks
;; for one and gets its number, waits until the page's title says that one is
;; made, then asks for it.
(defvar +my/excalidraw-png-timeout 15
  "Seconds a drawing's page is given to make its PNG.")

(defun +my/excalidraw--png-asked (number)
  "A page's answer to asking for a PNG: its NUMBER (\"0\": not ready)."
  (when +my/webkit-answering
    (xwidget-put +my/webkit-answering 'png-asked
                 (if (stringp number) (string-to-number number) 0))))

(defun +my/excalidraw--png-received (answer)
  "A page's PNG: ANSWER, \"NUMBER\\nBASE64\" (see above)."
  (when +my/webkit-answering
    (xwidget-put +my/webkit-answering 'png (+my/excalidraw--versioned answer))))

(defun +my/excalidraw--png-made-p (xwidget number)
  "Non-nil once XWIDGET's page says its PNG NUMBER is made."
  (>= (+my/excalidraw--number (+my/excalidraw--state xwidget) :png) number))

(defun +my/excalidraw-png (file)
  "Write the current buffer's drawing as a PNG into FILE (see
config/excalidraw.el); return FILE. An error if nothing is drawn, or if its
page doesn't make it in `+my/excalidraw-png-timeout' seconds."
  (let ((xwidget (or (+my/webkit-xwidget) (car (+my/webkit-xwidgets)))))
    (unless (and (derived-mode-p '+my/excalidraw-mode) xwidget)
      (user-error "No drawing shown here"))
    (xwidget-put xwidget 'png-asked nil)
    (xwidget-put xwidget 'png nil)
    (+my/webkit-ask (format "window.exd ? exd.png(%d) : '0'" +my/excalidraw-png-scale)
                    #'+my/excalidraw--png-asked xwidget)
    (let ((number (+my/webkit-wait (lambda () (xwidget-get xwidget 'png-asked)) 5)))
      (unless (and number (> number 0))
        (user-error "The drawing isn't ready yet"))
      (unless (+my/webkit-wait (lambda () (+my/excalidraw--png-made-p xwidget number))
                               +my/excalidraw-png-timeout)
        (error "The drawing's PNG wasn't made in %d s" +my/excalidraw-png-timeout))
      (+my/webkit-ask "window.exd ? exd.pngData() : '0\\n'" #'+my/excalidraw--png-received xwidget)
      (pcase-let ((`(,made . ,data) (or (+my/webkit-wait (lambda () (xwidget-get xwidget 'png)) 5)
                                        (error "The drawing's PNG didn't come from its page"))))
        (cond ((/= made number) (error "The drawing's PNG changed meanwhile: try again"))
              ((string-empty-p data) (user-error "Nothing is drawn"))
              ((string-prefix-p "error: " data)
               (error "The drawing's PNG: %s" (substring data (length "error: ")))))
        (make-directory (file-name-directory (expand-file-name file)) t)
        (let ((coding-system-for-write 'binary))
          (with-temp-file file
            (set-buffer-multibyte nil)
            (insert (base64-decode-string data))))
        file))))
