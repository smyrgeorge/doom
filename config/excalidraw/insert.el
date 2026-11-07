;;; $DOOMDIR/config/excalidraw/insert.el -*- lexical-binding: t; -*-
;; New drawings, links to them, Option+Enter. Loaded from config/excalidraw.el.

;; INSERTING (see config/excalidraw.el)

(defvar-local +my/excalidraw--save-new nil
  "Non-nil: save the drawing once its page has made it (a new one, see
INSERTING).")

(defun +my/excalidraw--dir-here ()
  "The folder of the current buffer's file."
  (if buffer-file-name (file-name-directory buffer-file-name) default-directory))

(defun +my/excalidraw--new-name (dir)
  "A drawing's file in DIR no file has: drawing.excalidraw.svg, drawing-2..."
  (let ((n 1)
        file)
    (while (and (< n 1000)
                (file-exists-p (setq file (expand-file-name
                                           (if (= n 1) "drawing.excalidraw.svg"
                                             (format "drawing-%d.excalidraw.svg" n))
                                           dir))))
      (setq n (1+ n)))
    file))

(defun +my/excalidraw--drawing-name (file)
  "FILE, a drawing's: with .excalidraw.svg after it unless it has a drawing's
extension."
  (if (let ((case-fold-search t))
        (string-match-p "\\.excalidraw\\(?:\\.svg\\)?\\'" file))
      file
    (concat file ".excalidraw.svg")))

(defun +my/excalidraw--link (file)
  "A link from the current buffer to drawing FILE, as an image: Markdown's,
Org's; elsewhere its path. Relative to the buffer's file."
  (let ((path (file-relative-name file (+my/excalidraw--dir-here))))
    (cond ((derived-mode-p 'markdown-mode)
           (format "![](%s)" (replace-regexp-in-string " " "%20" path t t)))
          ((derived-mode-p 'org-mode)
           (format "[[file:%s]]" path))
          (t path))))

(defun +my/excalidraw--at-point ()
  "The drawing a link at point names, if its file exists."
  (require 'thingatpt)
  (require 'url-util)
  (save-excursion
    (let ((case-fold-search t))
      (when (thing-at-point-looking-at "[^][ \t\n()<>\"'|]+\\.excalidraw\\(?:\\.svg\\)?" 500)
        (let* ((path (url-unhex-string (match-string-no-properties 0)))
               (file (expand-file-name (string-remove-prefix "file:" path)
                                       (+my/excalidraw--dir-here))))
          (and (file-exists-p file) file))))))

(defun +my/excalidraw-open (file &optional save-new action)
  "Open drawing FILE beside the selected window, on its right (it takes
focus); SAVE-NEW: saved once its page has made it (a new one). ACTION, a
`display-buffer' action, shows it elsewhere."
  (let ((buffer (find-file-noselect file)))
    (when save-new
      (with-current-buffer buffer
        (setq +my/excalidraw--save-new t)))
    (pop-to-buffer buffer
                   (or action
                       `((display-buffer-reuse-window display-buffer-in-direction)
                         (direction . right)
                         (window-width . ,(/ (window-total-width) 2)))))
    buffer))

(defun +my/excalidraw-insert (file)
  "Link a new drawing FILE at point, as an image, and open it beside (see
above); an existing FILE is linked and opened."
  (interactive
   (list (read-file-name "New drawing: " (+my/excalidraw--dir-here) nil nil
                         (file-name-nondirectory
                          (+my/excalidraw--new-name (+my/excalidraw--dir-here))))))
  (barf-if-buffer-read-only)
  (let* ((file (expand-file-name (+my/excalidraw--drawing-name file)))
         (new (not (file-exists-p file))))
    (when new
      (make-directory (file-name-directory file) t))
    (insert (+my/excalidraw--link file))
    (+my/excalidraw-open file new)))

;; OPTION+ENTER (config/editor/actions.el)
(defun +my/context-actions-excalidraw ()
  "Drawings: edit the one a link at point names; in Markdown and Org, insert
a new one."
  (let ((file (+my/excalidraw--at-point)))
    (append
     (when file
       (list (list "Drawing" "Edit the drawing" (lambda () (+my/excalidraw-open file)))))
     (when (and (derived-mode-p 'markdown-mode 'org-mode) (not buffer-read-only))
       (list (list "Drawing" "Insert a new drawing"
                   (lambda () (call-interactively #'+my/excalidraw-insert))))))))

(when (boundp '+my/context-action-providers)
  (add-to-list '+my/context-action-providers #'+my/context-actions-excalidraw t))
