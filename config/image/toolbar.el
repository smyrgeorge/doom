;;; $DOOMDIR/config/image/toolbar.el -*- lexical-binding: t; -*-
;; The toolbar, in the header line. Loaded from config/image.el.

(defvar image-transform-resize)

(defface +my/image-toolbar-button '((t :inherit header-line))
  "A button of the images' toolbar.")

(defface +my/image-toolbar-on '((t :inherit (font-lock-keyword-face header-line)))
  "A toolbar button whose setting is on (Fit, Sharp, Diff...).")

(defface +my/image-toolbar-off '((t :inherit (shadow header-line)))
  "A toolbar button that can't be used here.")

(defface +my/image-toolbar-text '((t :inherit (shadow header-line)))
  "The toolbar's text: the image's place in its folder, zoom, size.")

;; BUTTONS
(defconst +my/image--icons
  '((previous    "nf-cod-chevron_left")
    (next        "nf-cod-chevron_right")
    (zoom-out    "nf-cod-zoom_out")
    (zoom-in     "nf-cod-zoom_in")
    (fit         "nf-cod-screen_full"       "Fit")
    (actual      nil                        "1:1")
    (rotate-left "nf-md-rotate_left")
    (rotate      "nf-md-rotate_right")
    (flip        "nf-md-flip_horizontal")
    (flip-v      "nf-md-flip_vertical")
    (crop        "nf-md-crop"               "Crop")
    (play        "nf-cod-play")
    (pause       "nf-cod-debug_pause")
    (sharp       "nf-md-grid"               "Sharp")
    (copy        "nf-cod-copy"              "Copy")
    (diff        "nf-cod-diff"              "Diff")
    (save        "nf-md-content_save"       "Save")
    (preview     "nf-cod-link_external"     "Preview")
    (finder      "nf-md-apple_finder"))
  "(NAME NERD-ICON LABEL): a button's icon and label (either can be nil).")

(defconst +my/image--fallbacks
  '((previous . "‹") (next . "›") (zoom-out . "−") (zoom-in . "+")
    (rotate-left . "⟲") (rotate . "⟳") (flip . "⇋") (flip-v . "⇵")
    (play . "▶") (pause . "⏸") (finder . "Finder"))
  "Icons without a label, as text where Nerd icons aren't loaded.")

(defun +my/image--icon-spec (name)
  "Button NAME's (NAME NERD-ICON LABEL) (see `+my/image--icons'): on Linux,
Preview is Open (the default app) and Finder a folder (the file manager)."
  (pcase (and (not (+my/macos-p)) name)
    ('preview '(preview "nf-cod-link_external" "Open"))
    ('finder '(finder "nf-md-folder_open"))
    (_ (assq name +my/image--icons))))

(defun +my/image--icon (name)
  "Button NAME's icon and label (see `+my/image--icons')."
  (pcase-let* ((`(,_ ,icon ,label) (+my/image--icon-spec name))
               (glyph (and icon (fboundp 'nerd-icons-codicon)
                           (ignore-errors
                             (funcall (if (string-prefix-p "nf-md-" icon)
                                          #'nerd-icons-mdicon
                                        #'nerd-icons-codicon)
                                      icon)))))
    (cond ((and glyph label) (concat glyph " " label))
          ((or glyph label))
          ((and (eq name 'finder) (not (+my/macos-p))) "Folder")
          (t (alist-get name +my/image--fallbacks)))))

(defvar +my/image--click-maps (make-hash-table :test #'eq)
  "A keymap per command clicked in the toolbar.")

(defun +my/image--click (event command)
  "COMMAND, clicked in the toolbar of EVENT's window: run in that window."
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (select-window window))
    (call-interactively command)))

(defun +my/image--click-map (command)
  (or (gethash command +my/image--click-maps)
      (puthash command
               (let ((map (make-sparse-keymap)))
                 ;; Not the header line's own: dragging it.
                 (define-key map [header-line down-mouse-1] #'ignore)
                 (define-key map [header-line mouse-1]
                             (lambda (event)
                               (interactive "e")
                               (+my/image--click event command)))
                 map)
               +my/image--click-maps)))

(defun +my/image--button (name help command &optional state)
  "Button NAME calling COMMAND when clicked, HELP its tooltip. STATE: on (its
setting on), off (can't be used here) or nil."
  (let ((text (concat " " (+my/image--icon name) " ")))
    (add-face-text-property 0 (length text)
                            (pcase state
                              ('on '+my/image-toolbar-on)
                              ('off '+my/image-toolbar-off)
                              (_ '+my/image-toolbar-button))
                            t text)
    (if (eq state 'off)
        (propertize text 'help-echo help)
      (propertize text
                  ;; A mouse-face of its own (a new list, not `eq' to the
                  ;; next button's): Emacs highlights the whole run of text
                  ;; whose mouse-face is the same, buttons side by side as one.
                  'mouse-face (list 'header-line-highlight)
                  'pointer 'hand
                  'help-echo help
                  'local-map (+my/image--click-map command)))))

(defun +my/image--text (text)
  (propertize text 'face '+my/image-toolbar-text))

(defun +my/image--separator ()
  (+my/image--text " │ "))

;; THE TOOLBAR
(defun +my/image--toolbar-left ()
  "The toolbar's buttons on the left: the folder, zoom, edits, animation."
  (let* ((file (and buffer-file-name (not +my/image--head-of)))
         (scale (or +my/image--zoom-target (+my/image-scale)))
         (editable (+my/image--editable-p)))
    (concat
     (if +my/image--head-of
         (concat (propertize (format " HEAD %s " +my/image--head-commit)
                             'face '+my/image-toolbar-on)
                 (+my/image--separator))
       (when file
         (pcase-let ((`(,index . ,count) (+my/image--position)))
           (concat (+my/image--button 'previous "Previous image in the folder (K)"
                                      #'+my/image-previous (and (< count 2) 'off))
                   (+my/image--text (format "%d/%d" (1+ index) count))
                   (+my/image--button 'next "Next image in the folder (J)"
                                      #'+my/image-next (and (< count 2) 'off))
                   (+my/image--separator)))))
     (+my/image--button 'zoom-out "Zoom out (-, Cmd+-)" #'+my/image-zoom-out)
     ;; %% for the header line: % starts its constructs (%b...).
     (+my/image--text (if scale (format "%d%%%%" (round (* 100 scale))) "–"))
     (+my/image--button 'zoom-in "Zoom in (+, Cmd+=)" #'+my/image-zoom-in)
     (+my/image--button 'fit "Fit the window (W)" #'+my/image-fit
                        (and (eq image-transform-resize 'fit-window) 'on))
     (+my/image--button 'actual "Actual size (0, Cmd+0)" #'+my/image-actual-size
                        (and scale (< (abs (- scale 1.0)) 0.005) 'on))
     (when editable
       (concat (+my/image--separator)
               (+my/image--button 'rotate-left "Rotate anticlockwise (R)" #'+my/image-rotate-left)
               (+my/image--button 'rotate "Rotate clockwise (r)" #'+my/image-rotate)
               (+my/image--button 'flip "Flip horizontally (f)" #'+my/image-flip)
               (+my/image--button 'flip-v "Flip vertically (F)" #'+my/image-flip-vertically)
               (+my/image--button 'crop "Crop: drag, RET crops, q cancels (c)" #'+my/image-crop)))
     (+my/image--separator)
     (when image-multi-frame
       (if (+my/image-playing-p)
           (+my/image--button 'pause "Pause the animation (RET)" #'+my/image-toggle-animation)
         (+my/image--button 'play "Play the animation (RET)" #'+my/image-toggle-animation)))
     (+my/image--button 'sharp "Sharp pixels: no smoothing (SPC m s)" #'+my/image-toggle-sharp
                        (and (+my/image--sharp-p) 'on)))))

(defun +my/image--toolbar-right (level)
  "The toolbar's right side: the image's size, Copy, Diff, Save, Preview,
Finder. LEVEL 0 all of it, 1 without the size, 2 Copy only (a narrow window)."
  (let ((file (and buffer-file-name (not +my/image--head-of))))
    (concat
     (when (< level 1)
       (concat (+my/image--text (+my/image-info)) " "))
     (+my/image--button 'copy (format "Copy the image (y, %s)" (+my/os-key-name "Cmd+C" "Ctrl+Shift+C"))
                        #'+my/image-copy)
     (when (and file (< level 2))
       (concat
        (+my/image--button 'diff "The image as in git's HEAD, on the left (SPC m g)"
                           #'+my/image-diff (and (+my/image--head-shown-p) 'on))
        (when (buffer-modified-p)
          (+my/image--button 'save "Save the edited image (SPC f s)" #'+my/image-save 'on))
        (+my/image--button 'preview (format "Open in %s (SPC m p)" (+my/os-app-name 'viewer))
                           #'+my/image-open-in-preview)
        (+my/image--button 'finder (format "Show in %s (SPC m f)" (+my/os-app-name 'files))
                           #'+my/image-show-in-finder))))))

(defvar-local +my/image--toolbar-cache nil
  "(KEY . TEXT): the toolbar last made, and what it was made from.")

(defun +my/image--toolbar-key ()
  "What the toolbar shows depends on: made again when it changes."
  (list (window-body-width nil t) (buffer-chars-modified-tick) (buffer-modified-p)
        image-transform-resize +my/image--zoom-target (+my/image-scale)
        (+my/image--sharp-p) (and image-multi-frame (+my/image-playing-p) t)
        (+my/image--head-shown-p) +my/image--head-of (and buffer-file-name (+my/image--position))
        (and (fboundp 'nerd-icons-codicon) t)))

(defun +my/image--toolbar ()
  "The toolbar (see config/image.el): buttons on the left, the image's size
and the rest on the right, as much of it as the window fits. In the header
line, made again only when what it shows changes."
  (when (+my/image--spec)
    (let ((key (+my/image--toolbar-key)))
      (unless (equal (car +my/image--toolbar-cache) key)
        (setq +my/image--toolbar-cache (cons key (+my/image--make-toolbar))))
      (cdr +my/image--toolbar-cache))))

(defun +my/image--make-toolbar ()
  (let* ((width (window-body-width nil t))
         (left (concat " " (+my/image--toolbar-left)))
         (left-width (string-pixel-width left))
         (right (seq-find (lambda (right) (<= (+ left-width (string-pixel-width right)) width))
                          (mapcar #'+my/image--toolbar-right '(0 1))
                          (+my/image--toolbar-right 2))))
    (concat left
            (propertize " " 'display
                        `(space :align-to (- right (,(string-pixel-width right)))))
            right)))
