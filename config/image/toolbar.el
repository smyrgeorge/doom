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
    (finder      "nf-md-apple_finder")
    (more        "nf-cod-ellipsis"))
  "(NAME NERD-ICON LABEL): a button's icon and label (either can be nil).")

(defconst +my/image--fallbacks
  '((previous . "‹") (next . "›") (zoom-out . "−") (zoom-in . "+")
    (rotate-left . "⟲") (rotate . "⟳") (flip . "⇋") (flip-v . "⇵")
    (play . "▶") (pause . "⏸") (finder . "Finder") (more . "…"))
  "Icons without a label, as text where Nerd icons aren't loaded.")

(defun +my/image--icon-spec (name)
  "Button NAME's (NAME NERD-ICON LABEL) (see `+my/image--icons'): on Linux,
Preview is Open (the default app) and Finder a folder (the file manager)."
  (pcase (and (not (+my/macos-p)) name)
    ('preview '(preview "nf-cod-link_external" "Open"))
    ('finder '(finder "nf-md-folder_open"))
    (_ (assq name +my/image--icons))))

(defun +my/image--icon (name &optional short)
  "Button NAME's icon and label (see `+my/image--icons'); SHORT, its icon
alone if it has one."
  (pcase-let* ((`(,_ ,icon ,label) (+my/image--icon-spec name))
               (glyph (and icon (fboundp 'nerd-icons-codicon)
                           (ignore-errors
                             (funcall (if (string-prefix-p "nf-md-" icon)
                                          #'nerd-icons-mdicon
                                        #'nerd-icons-codicon)
                                      icon)))))
    (cond ((and glyph label) (if short glyph (concat glyph " " label)))
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

(defun +my/image--button (name help command &optional state short)
  "Button NAME calling COMMAND when clicked, HELP its tooltip. STATE: on (its
setting on), off (can't be used here) or nil. SHORT: its icon alone, one
space before it instead of one on each side."
  (let ((text (if short
                  (concat " " (+my/image--icon name t))
                (concat " " (+my/image--icon name) " "))))
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
;; As wide as its window, no wider: in a narrow one it leaves out, first to
;; last, the groups of `+my/image--narrowing', the buttons left out in the
;; menu of a … button at its right end, with their keys.
(defconst +my/image--narrowing
  '(size apps edits view folder zoom tight save diff copy)
  "What a narrow window's toolbar leaves out, first to last: the image's size;
Diff (HEAD not shown), Preview and Finder; rotate, flip and crop; Fit, 1:1
and Sharp; the folder's ‹ n/m › (HEAD's commit); zoom and play / pause; the
room around Copy, Diff and Save, and their labels (icons kept); then Save,
Diff and Copy.")

(defun +my/image--toolbar-parts (level)
  "The toolbar without the first LEVEL groups of `+my/image--narrowing':
\(LEFT RIGHT MENU), its two sides and the buttons left out, (HELP COMMAND
STATE) each."
  (let* ((out (seq-take +my/image--narrowing level))
         (file (and buffer-file-name (not +my/image--head-of)))
         (scale (or +my/image--zoom-target (+my/image-scale)))
         (head (+my/image--head-shown-p))
         (menu nil))
    (cl-flet ((button (group name help command &optional state)
                (if (not (memq group out))
                    (+my/image--button name help command state (memq 'tight out))
                  (unless (eq state 'off)
                    (push (list help command state) menu))
                  nil)))
      (let* ((place
              (cond
               (+my/image--head-of
                (propertize (if (memq 'folder out) " HEAD " (format " HEAD %s " +my/image--head-commit))
                            'face '+my/image-toolbar-on
                            'help-echo (format "The image as in git's HEAD (%s)" +my/image--head-commit)))
               (file
                (pcase-let* ((`(,index . ,count) (+my/image--position))
                             (state (and (< count 2) 'off)))
                  (concat (button 'folder 'previous "Previous image in the folder (K)"
                                  #'+my/image-previous state)
                          (unless (memq 'folder out)
                            (+my/image--text (format "%d/%d" (1+ index) count)))
                          (button 'folder 'next "Next image in the folder (J)"
                                  #'+my/image-next state))))))
             (zoom
              (concat (button 'zoom 'zoom-out "Zoom out (-, Cmd+-)" #'+my/image-zoom-out)
                      (unless (memq 'zoom out)
                        ;; %% for the header line: % starts its constructs (%b...).
                        (+my/image--text (if scale (format "%d%%%%" (round (* 100 scale))) "–")))
                      (button 'zoom 'zoom-in "Zoom in (+, Cmd+=)" #'+my/image-zoom-in)
                      (button 'view 'fit "Fit the window (W)" #'+my/image-fit
                              (and (eq image-transform-resize 'fit-window) 'on))
                      (button 'view 'actual "Actual size (0, Cmd+0)" #'+my/image-actual-size
                              (and scale (< (abs (- scale 1.0)) 0.005) 'on))))
             (edits
              (when (+my/image--editable-p)
                (concat (button 'edits 'rotate-left "Rotate anticlockwise (R)" #'+my/image-rotate-left)
                        (button 'edits 'rotate "Rotate clockwise (r)" #'+my/image-rotate)
                        (button 'edits 'flip "Flip horizontally (f)" #'+my/image-flip)
                        (button 'edits 'flip-v "Flip vertically (F)" #'+my/image-flip-vertically)
                        (button 'edits 'crop "Crop: drag, RET crops, q cancels (c)" #'+my/image-crop))))
             (looks
              (concat (when image-multi-frame
                        (if (+my/image-playing-p)
                            (button 'zoom 'pause "Pause the animation (RET)" #'+my/image-toggle-animation)
                          (button 'zoom 'play "Play the animation (RET)" #'+my/image-toggle-animation)))
                      (button 'view 'sharp "Sharp pixels: no smoothing (SPC m s)" #'+my/image-toggle-sharp
                              (and (+my/image--sharp-p) 'on))))
             (left (mapconcat #'identity
                              (seq-remove #'string-empty-p (delq nil (list place zoom edits looks)))
                              (+my/image--separator)))
             (right
              (concat
               (unless (memq 'size out)
                 (concat (+my/image--text (+my/image-info)) " "))
               (button 'copy 'copy (format "Copy the image (y, %s)" (+my/os-key-name "Cmd+C" "Ctrl+Shift+C"))
                       #'+my/image-copy)
               (when file
                 (concat
                  (button (if head 'diff 'apps) 'diff
                          (if head "Close git's HEAD (SPC m g)" "The image as in git's HEAD, beside it (SPC m g)")
                          #'+my/image-diff (and head 'on))
                  (when (buffer-modified-p)
                    (button 'save 'save "Save the edited image (SPC f s)" #'+my/image-save 'on))
                  (button 'apps 'preview (format "Open in %s (SPC m p)" (+my/os-app-name 'viewer))
                          #'+my/image-open-in-preview)
                  (button 'apps 'finder (format "Show in %s (SPC m f)" (+my/os-app-name 'files))
                          #'+my/image-show-in-finder))))))
        (setq menu (nreverse menu))
        (list (if (string-empty-p left) "" (concat " " left))
              (if menu
                  (concat right (+my/image--button 'more "What the toolbar leaves out here"
                                                   #'+my/image-toolbar-menu))
                right)
              menu)))))

(defun +my/image--toolbar-fit ()
  "The toolbar's widest form the selected window fits (see THE TOOLBAR):
\(LEFT RIGHT MENU), as `+my/image--toolbar-parts'."
  (let ((width (window-body-width nil t))
        (last (length +my/image--narrowing)))
    (cl-loop for level from 0 to last
             for parts = (+my/image--toolbar-parts level)
             when (or (= level last)
                      (<= (+ (string-pixel-width (nth 0 parts)) (string-pixel-width (nth 1 parts)))
                          width))
             return parts)))

(defun +my/image--menu (items)
  "A menu of ITEMS, (HELP COMMAND STATE) each: HELP its label, ticked if
STATE is on (as `+my/image--button's)."
  (let ((map (make-sparse-keymap "Image")))
    (dolist (item (reverse items) map)
      (pcase-let ((`(,help ,command ,state) item))
        (define-key map (vector command)
                    `(menu-item ,help ,command
                                ,@(when (eq state 'on) '(:button (:toggle . t)))))))))

(defun +my/image-toolbar-menu ()
  "The toolbar's … button: a menu of the buttons a narrow window leaves out,
with their keys."
  (interactive)
  (let ((items (nth 2 (+my/image--toolbar-fit))))
    (unless items
      (user-error "The toolbar shows all its buttons"))
    (popup-menu (+my/image--menu items))))

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
and the rest on the right, as much of it as the window fits (see THE
TOOLBAR). In the header line, made again only when what it shows changes."
  (when (+my/image--spec)
    (let ((key (+my/image--toolbar-key)))
      (unless (equal (car +my/image--toolbar-cache) key)
        (setq +my/image--toolbar-cache (cons key (+my/image--make-toolbar))))
      (cdr +my/image--toolbar-cache))))

(defun +my/image--make-toolbar ()
  (pcase-let ((`(,left ,right) (+my/image--toolbar-fit)))
    (concat left
            (propertize " " 'display
                        `(space :align-to (- right (,(string-pixel-width right)))))
            right)))
