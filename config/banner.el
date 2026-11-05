;;; $DOOMDIR/config/banner.el -*- lexical-binding: t; -*-
;; Notices at the top of a window, like IntelliJ's editor notifications.
;; Loaded from config.el.

;; ====== VARIABLES ======

;; BANNERS
;; A buffer can show notices at the top of its windows, under the tabs: a row
;; each, with an icon and colour for its type (info, warning, error), the
;; message, actions to click, and ✕ to close it. They stay put while scrolling,
;; and the header line (the file's path, or the sticky scopes) stays under them.
;; From code: (+my/banner-show ID TEXT :type 'warning :actions '(("Do" . fn)));
;; M-x +my/banner-close closes the first one.
;; (A header line is a single row of text. So it grows a row per notice, with
;; its own text in the bottom one, and a small frame without borders lays the
;; notices over the rows above. In a terminal the header line shows the first
;; notice instead, saying how many more there are.)
;;
;; Notices so far:
;; - long lines (warning): files with very long lines open in `so-long-mode',
;;   plain and unwrapped (see config/smooth.el); "Wrap lines" wraps them again,
;;   "Open normally" goes back to the file's own mode (both can make scrolling
;;   slow again).
(defvar +my/banner-types
  '((info    "nf-cod-info"    blue)
    (warning "nf-cod-warning" yellow)
    (error   "nf-cod-error"   red))
  "The kinds of notices: (TYPE ICON COLOUR), ICON a codicon (nerd-icons),
COLOUR a theme colour (`doom-color'): the icon's, and the row's tint.")

(defface +my/banner-info '((t :inherit header-line)) "An info notice's row.")

(defface +my/banner-warning '((t :inherit header-line)) "A warning notice's row.")

(defface +my/banner-error '((t :inherit header-line)) "An error notice's row.")

(defface +my/banner-action '((t :inherit link :underline nil :weight bold))
  "The actions in a notice.")

;; ====== CODE ======

(defvar-local +my/banner--list nil
  "The buffer's notices, top first: (ID TEXT ACTIONS TYPE).")

(defvar-local +my/banner--saved-header nil
  "`header-line-format' before the notices made room in it.")

(defconst +my/banner--header '(:eval (+my/banner--header-line))
  "Put before the header line's own content while there are notices.")

(defun +my/banner--ours-p ()
  (eq (car-safe header-line-format) +my/banner--header))

(defun +my/banner--install ()
  "Make room for the notices in the current buffer's header line."
  (unless (+my/banner--ours-p)
    (setq +my/banner--saved-header header-line-format)
    (setq-local header-line-format (list +my/banner--header header-line-format))))

(defun +my/banner--uninstall ()
  (when (+my/banner--ours-p)
    (setq-local header-line-format +my/banner--saved-header)))

(cl-defun +my/banner-show (id text &key (type 'info) actions)
  "Show notice ID at the top of the current buffer's windows: TEXT, of TYPE
(info, warning, error; see `+my/banner-types'), then ACTIONS to click, a list
of (LABEL . FUNCTION), FUNCTION called in the buffer. Showing ID again replaces
it in place."
  (let ((notice (list id text actions type)))
    (setq +my/banner--list
          (if (assq id +my/banner--list)
              (mapcar (lambda (n) (if (eq (car n) id) notice n)) +my/banner--list)
            (append +my/banner--list (list notice)))))
  (+my/banner--install)
  (force-mode-line-update t)
  (+my/banner--sync))

(defun +my/banner-close (&optional id)
  "Close notice ID, by default the first one."
  (interactive)
  (setq +my/banner--list (if id
                             (cl-remove id +my/banner--list :key #'car)
                           (cdr +my/banner--list)))
  (unless +my/banner--list
    (+my/banner--uninstall))
  (force-mode-line-update t)
  (+my/banner--sync))

;;; A notice's row

(defun +my/banner--face (type)
  (intern (format "+my/banner-%s" (if (assq type +my/banner-types) type 'info))))

(defvar +my/banner--row-map
  (let ((map (make-sparse-keymap)))
    ;; Clicks and the wheel on a notice do nothing (they'd select its frame or
    ;; scroll it).
    (dolist (event '(down-mouse-1 mouse-1 double-mouse-1 triple-mouse-1 drag-mouse-1
                     down-mouse-2 mouse-2 down-mouse-3 mouse-3
                     wheel-up wheel-down wheel-left wheel-right
                     double-wheel-up double-wheel-down triple-wheel-up triple-wheel-down))
      (define-key map (vector event) #'ignore))
    map)
  "Keys on a notice's row.")

(defun +my/banner--refocus ()
  "After a click on a notice, keyboard input stays with the window it's about."
  (when-let* ((parent (frame-parent (selected-frame))))
    (select-frame-set-input-focus parent)))

(defun +my/banner--button (label function face buffer header &optional help)
  "LABEL (of FACE) calling FUNCTION in BUFFER when clicked. HEADER: it's in the
header line (a terminal's), else on a row of the notices' frame."
  (let ((map (make-sparse-keymap))
        (command (lambda () (interactive)
                   (when (buffer-live-p buffer)
                     (with-current-buffer buffer (funcall function)))
                   (+my/banner--refocus))))
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

(defun +my/banner--row (notice buffer &optional header more)
  "NOTICE's row, its actions run in BUFFER: on the notices' frame, or in the
header line if HEADER (then MORE: how many other notices to mention)."
  (pcase-let* ((`(,id ,text ,actions ,type) notice)
               (face (+my/banner--face type))
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
     (when (and more (> more 0))
       (propertize (format "    (%d more)" more) 'face `(shadow ,face)))
     (funcall plain " " 'display '(space :align-to (- right 4)))
     (+my/banner--button " ✕ " (lambda () (+my/banner-close id)) face buffer header
                         "mouse-1: close")
     ;; To the edge: in the header line over the right margin (the stripe) and
     ;; fringe too, else they keep the header line's own colour.
     (funcall plain " " 'display (if header
                                     '(space :align-to (+ right right-margin right-fringe))
                                   '(space :align-to right))))))

;;; Room in the header line

(defun +my/banner--row-height (&optional window)
  "The height of a notice's row in WINDOW: a line of the header line's font."
  (or (ignore-errors (window-font-height window 'header-line))
      (frame-char-height (window-frame window))))

(defun +my/banner--descent (&optional window)
  "The descent of the header line's font in WINDOW."
  (or (ignore-errors
        (aref (font-info (face-font 'header-line (window-frame window) ?a)
                         (window-frame window))
              9))
      0))

(defvar +my/banner--spacers (make-hash-table :test #'equal))

(defun +my/banner--spacer (rows alone)
  "An invisible image, a pixel wide and tall enough for ROWS notice rows above
the header line's text (none if ALONE), sitting on its baseline: it makes the
header line that much taller, its text in the bottom row."
  (let* ((row (+my/banner--row-height))
         (height (if alone
                     (max 1 (- (* rows row) (+my/banner--descent)))
                   (+ (* rows row) (- row (+my/banner--descent))))))
    (or (gethash height +my/banner--spacers)
        (puthash height
                 (propertize
                  " " 'display
                  (create-image
                   (concat "/* XPM */ static char *s[] = {\"1 " (number-to-string height)
                           " 1 1\", \". c None\","
                           (mapconcat (lambda (_) "\".\"") (number-sequence 1 height) ",")
                           "};")
                   'xpm t :ascent 100))
                 +my/banner--spacers))))

(defun +my/banner--header-line ()
  "Before the header line's own content: room for the notices (in a terminal,
the first one, which takes the whole row)."
  (when +my/banner--list
    (if (display-graphic-p)
        (+my/banner--spacer (length +my/banner--list) (null +my/banner--saved-header))
      (+my/banner--row (car +my/banner--list) (current-buffer) t
                       (length (cdr +my/banner--list))))))

;;; The notices' frames

(defvar +my/banner--frames nil
  "(WINDOW FRAME KEY) for each window that shows (or showed) notices: FRAME
lays them over its header line, KEY is what it shows.")

(defvar +my/banner--theme 0 "Bumped when the theme changes: redraw the notices.")

(defun +my/banner--make-frame (parent)
  "A frame without borders, not taking focus, inside PARENT, for notices."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (frame-resize-pixelwise t)
         (buffer (generate-new-buffer " *+my/banner*"))
         (selected (selected-frame))
         (frame (make-frame
                 `((parent-frame . ,parent)
                   (title . "notices")
                   (fullscreen . nil)
                   (no-accept-focus . t)
                   (no-focus-on-map . t)
                   (min-width . 0)
                   (min-height . 0)
                   (border-width . 0)
                   (internal-border-width . 0)
                   (child-frame-border-width . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)
                   (left-fringe . 0)
                   (right-fringe . 0)
                   (menu-bar-lines . 0)
                   (tool-bar-lines . 0)
                   (tab-bar-lines . 0)
                   (line-spacing . 0)
                   (unsplittable . t)
                   (no-other-frame . t)
                   (undecorated . t)
                   (visibility . nil)
                   (cursor-type . nil)
                   (minibuffer . ,(minibuffer-window parent))
                   (width . 1)
                   (height . 1)
                   (no-special-glyphs . t)
                   (desktop-dont-save . t)
                   (font . ,(face-attribute 'default :font parent))))))
    (unless (eq (selected-frame) selected)
      (select-frame selected 'norecord))
    (with-current-buffer buffer
      (setq-local mode-line-format nil
                  header-line-format nil
                  tab-line-format nil
                  cursor-type nil
                  cursor-in-non-selected-windows nil
                  truncate-lines t
                  display-line-numbers nil
                  show-trailing-whitespace nil
                  left-margin-width nil
                  right-margin-width nil
                  buffer-read-only t))
    (let ((window (frame-root-window frame)))
      (set-window-parameter window 'mode-line-format 'none)
      (set-window-parameter window 'header-line-format 'none)
      (set-window-parameter window 'tab-line-format 'none)
      (set-window-buffer window buffer)
      (set-window-dedicated-p window t))
    frame))

(defun +my/banner--delete-frame (frame)
  (when (frame-live-p frame)
    (let ((buffer (window-buffer (frame-root-window frame))))
      (delete-frame frame t)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun +my/banner--show-in (window)
  "Lay the notices of WINDOW's buffer over its header line."
  (let* ((buffer (window-buffer window))
         (notices (buffer-local-value '+my/banner--list buffer))
         (entry (assq window +my/banner--frames)))
    ;; In case the header line was set anew (e.g. by a mode) since.
    (with-current-buffer buffer (+my/banner--install))
    (unless (and entry (frame-live-p (nth 1 entry)))
      (when entry (+my/banner--delete-frame (nth 1 entry)))
      (setq entry (list window (+my/banner--make-frame (window-frame window)) nil))
      (setq +my/banner--frames
            (cons entry (cl-remove window +my/banner--frames :key #'car))))
    (let* ((frame (nth 1 entry))
           (key (list buffer notices +my/banner--theme))
           ;; From the frame's native edges, like the frame's own position.
           (edges (window-pixel-edges window))
           (left (nth 0 edges))
           (top (+ (nth 1 edges) (window-tab-line-height window)))
           (width (- (window-pixel-width window)
                     (window-right-divider-width window)
                     (window-scroll-bar-width window)))
           (height (* (length notices) (+my/banner--row-height window)))
           (geometry (list left top width height))
           (frame-resize-pixelwise t))
      (unless (equal key (nth 2 entry))
        (with-current-buffer (window-buffer (frame-root-window frame))
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (mapconcat (lambda (notice) (+my/banner--row notice buffer)) notices "\n"))
            (goto-char (point-min))))
        (set-frame-parameter frame 'background-color
                             (face-background (+my/banner--face (nth 3 (car notices))) nil t))
        (setf (nth 2 entry) key))
      (unless (equal geometry (frame-parameter frame '+my/banner-geometry))
        (set-frame-size frame width height t)
        (set-frame-position frame left top)
        (set-frame-parameter frame '+my/banner-geometry geometry))
      (unless (frame-visible-p frame)
        (make-frame-visible frame)))))

(defun +my/banner--sync ()
  "Show each window's notices over its header line, and hide those of windows
that no longer have any."
  (let (wanted)
    (dolist (frame (frame-list))
      (when (and (not (frame-parent frame))
                 (display-graphic-p frame)
                 (frame-visible-p frame))
        (dolist (window (window-list frame 'nomini))
          (when (buffer-local-value '+my/banner--list (window-buffer window))
            (push window wanted)))))
    (setq +my/banner--frames
          (cl-remove-if (lambda (entry)
                          (cond ((memq (car entry) wanted) nil)
                                ((and (window-live-p (car entry))
                                      (frame-live-p (nth 1 entry)))
                                 (make-frame-invisible (nth 1 entry) t)
                                 nil)
                                (t (+my/banner--delete-frame (nth 1 entry)) t)))
                        +my/banner--frames))
    (dolist (window wanted)
      (condition-case err
          (+my/banner--show-in window)
        (error (message "Notices: %s" (error-message-string err)))))))

(defvar +my/banner--sync-timer nil)

(defun +my/banner--sync-soon (&rest _)
  "Sync right after this redisplay (frames can't be made during it)."
  (unless (timerp +my/banner--sync-timer)
    (setq +my/banner--sync-timer
          (run-at-time 0 nil (lambda ()
                               (setq +my/banner--sync-timer nil)
                               (+my/banner--sync))))))

(defun +my/banner--window-change-h (frame)
  ;; Windows split, closed, resized, or showing another buffer.
  (unless (frame-parent frame)
    (+my/banner--sync-soon)))

(add-hook 'window-state-change-functions #'+my/banner--window-change-h)

;; A new major mode drops the buffer's notices.
(add-hook 'change-major-mode-hook #'+my/banner--sync-soon)

(defun +my/banner-faces-h ()
  "Each type's row tinted with its theme colour, like IntelliJ's notices."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (face-background 'default nil t)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (pcase-dolist (`(,type ,_ ,colour) +my/banner-types)
          (when-let* ((tint (doom-color colour))
                      ((stringp tint)))
            (set-face-attribute (+my/banner--face type) nil
                                :inherit 'header-line
                                :background (doom-blend tint bg 0.2)
                                :foreground (face-foreground 'default nil t)))))))
  (cl-incf +my/banner--theme)
  (+my/banner--sync-soon))

(+my/banner-faces-h)

(add-hook 'doom-load-theme-hook #'+my/banner-faces-h)

;;; Notice (warning): very long lines aren't wrapped nor highlighted

(defun +my/banner--group-digits (n)
  "N with thousands separators: 51997 -> \"51,997\"."
  (let ((s (number-to-string n)))
    (while (string-match "\\([0-9]\\)\\([0-9]\\{3\\}\\)\\(,\\|\\'\\)" s)
      (setq s (replace-match "\\1,\\2\\3" t nil s)))
    s))

(defun +my/banner-long-lines-h ()
  "In `so-long-mode' (very long lines), say the file is shown plain and unwrapped."
  (when (derived-mode-p 'so-long-mode)
    (+my/banner-show
     'long-lines
     (format "This file has very long lines (up to %s characters): shown without highlighting%s, to keep scrolling smooth."
             (+my/banner--group-digits (cadr (buffer-line-statistics)))
             (if truncate-lines " and unwrapped" ""))
     :type 'warning
     :actions `(,@(and truncate-lines '(("Wrap lines" . +my/banner--wrap-lines)))
                ("Open normally" . +my/banner--open-normally)))))

(defun +my/banner--wrap-lines ()
  (setq-local truncate-lines nil)
  ;; Same notice, without the part about wrapping.
  (+my/banner-long-lines-h))

(defun +my/banner--open-normally ()
  ;; Back to the file's own mode. Not `so-long-revert': Doom's action keeps
  ;; what to undo in a buffer-local variable that entering `so-long-mode'
  ;; wipes, so it did nothing.
  (so-long-mode-revert))

(add-hook 'so-long-hook #'+my/banner-long-lines-h)
