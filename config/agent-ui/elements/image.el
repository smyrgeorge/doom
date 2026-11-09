;;; $DOOMDIR/config/agent-ui/elements/image.el -*- lexical-binding: t; -*-
;; Agent UI's image: a picture file (an Excalidraw drawing's .excalidraw.svg
;; too) shown in a graphic Emacs. Loaded from config/agent-ui/elements.el.
;;
;; At most the pane's width (WIDTH: a share of it) and HEIGHT lines, never
;; above its own size; in a terminal, a line naming it. RET or a click opens
;; it (`agent-ui-open-file-function': the image viewer, Excalidraw for a
;; drawing). A file that isn't there is said, not an error.

(require 'subr-x)

(defcustom agent-ui-open-file-function #'find-file-other-window
  "Opens a file an element shows (an image), given its name."
  :type 'function :group 'agent-ui)

(defun agent-ui-image--line (props ctx &optional why)
  "The line naming PROPS' image (in a terminal; WHY it isn't shown), CTX's
width at most."
  (let* ((file (plist-get props :file))
         (alt (plist-get props :alt)))
    (agent-ui-truncate
     (concat (propertize "▣ " 'face 'agent-ui-accent)
            (agent-ui-button (abbreviate-file-name file)
                             (lambda () (funcall agent-ui-open-file-function file))
                             "RET: open the image")
            (if alt (concat "  " alt) "")
            (if why (propertize (concat "  (" why ")") 'face 'agent-ui-muted) ""))
     (plist-get ctx :width))))

(defun agent-ui-image--text (props ctx)
  (agent-ui-image--line props ctx (unless (file-readable-p (plist-get props :file)) "not found")))

(defun agent-ui-image--gui (props ctx)
  (let ((file (plist-get props :file)))
    (cond
     ((not (file-readable-p file)) (agent-ui-image--line props ctx "not found"))
     ((not (image-supported-file-p file)) (agent-ui-image--line props ctx "not an image Emacs shows"))
     (t
      (let* ((width (round (* (plist-get ctx :width) (plist-get ctx :char-width)
                              (/ (plist-get props :width) 100.0))))
             (height (* (plist-get props :height) (plist-get ctx :line-height)))
             (image (create-image file nil nil :max-width width :max-height height :ascent 'center)))
        (concat (agent-ui-button (propertize " " 'display image)
                                 (lambda () (funcall agent-ui-open-file-function file))
                                 (format "%s: RET opens it" (abbreviate-file-name file)))
                (if-let* ((alt (plist-get props :alt)))
                    (concat "\n" (propertize alt 'face 'agent-ui-muted))
                  "")))))))

(agent-ui-define image
  "An image file (PNG, JPEG, GIF, WebP, SVG; an Excalidraw drawing's
.excalidraw.svg too), shown in a graphic Emacs at most WIDTH percent of the
pane wide and HEIGHT lines high (never above its own size); in a terminal,
a line naming it. RET opens it. FILE: relative to your directory."
  :props ((file file "The image file" :required t)
          (alt string "What it shows (said under it; a terminal's only text)")
          (width integer "At most this percentage of the pane's width" :default 100)
          (height integer "At most so many lines high" :default 20))
  :example (:title "The login page" :file "screenshots/login.png" :alt "After the fix" :width 60)
  :check (lambda (props)
           (unless (<= 1 (plist-get props :width) 100)
             (agent-ui--fail "image: width is a percentage, 1 to 100"))
           (unless (<= 1 (plist-get props :height) 200)
             (agent-ui--fail "image: height is lines, 1 to 200"))
           props)
  :text #'agent-ui-image--text
  :gui #'agent-ui-image--gui)
