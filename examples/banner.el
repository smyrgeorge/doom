;;; $DOOMDIR/examples/banner.el -*- lexical-binding: t; -*-
;; Example: notices at the top of a window (config/banner.el, docs/editor.md).
;; M-x +my/example-banner writes a minified catalog (one line, very long) to
;; the temp folder and opens it: it opens plain (`so-long-mode'), and the
;; config's own notice says so, a warning with its actions. Two more, of the
;; other kinds, say what notices are: an info one ("Another one" adds a
;; notice) and an error one ("Close them all"). ✕ closes one. The file is
;; deleted once it's closed.

;; ====== CODE ======

(defun +my/example-banner--json ()
  "A catalog of products as minified JSON: one line, far over the long-line
threshold."
  (concat "{\"products\":["
          (mapconcat (lambda (n)
                       (format "{\"id\":%d,\"name\":\"Product %d\",\"price\":%d.%02d,\"tags\":[\"fruit\",\"fresh\"],\"stock\":%d}"
                               n n (+ 1 (% (* n 7) 40)) (% (* n 13) 100) (% (* n 31) 500)))
                     (number-sequence 1 200) ",")
          "]}\n"))

(defun +my/example-banner--another ()
  "Another notice, an info one (see above)."
  (+my/banner-show (intern (format "example-%d" (random 100000)))
                   "Another notice: each has its row; they stay put while the text scrolls."
                   :type 'info))

(defun +my/example-banner--close-all ()
  "Close the notices, one by one."
  (while (bound-and-true-p +my/banner--list)
    (+my/banner-close)))

(defun +my/example-banner ()
  "Example: notices at the top of a window, of each kind (the file deleted
once closed). See examples/banner.el."
  (interactive)
  (let* ((dir (+my/example-folder "banner"))
         (file (+my/example-write dir "catalog.min.json" (+my/example-banner--json))))
    (delete-other-windows)
    (find-file file)
    ;; Very long lines: so-long-mode, and its notice (where Doom's global
    ;; so-long-mode isn't on, by hand).
    (unless (derived-mode-p 'so-long-mode)
      (so-long))
    (+my/banner-show 'example-info
                     "Notices sit at the top of a window, under its tabs: an icon and a colour for their kind, a message, actions to click, ✕ to close."
                     :type 'info
                     :actions '(("Another one" . +my/example-banner--another)))
    (+my/banner-show 'example-error
                     "An error notice (an example): its actions are buttons as the others'."
                     :type 'error
                     :actions '(("Close them all" . +my/example-banner--close-all)))
    (+my/example-delete-when-closed dir (list (current-buffer)))
    (message "Banner example: click a notice's actions or its ✕")
    (current-buffer)))

(provide 'example-banner)
