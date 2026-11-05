;;; $DOOMDIR/config/banner.el -*- lexical-binding: t; -*-
;; Notices at the top of a window, like IntelliJ's editor notifications.
;; Loaded from config.el.

;; ====== VARIABLES ======

;; BANNERS
;; A buffer can show notices in a bar at the top of its windows (the header
;; line, which stays put while scrolling): an icon and colour for its type
;; (info, warning, error), the message, actions to click, and ✕ to close it.
;; One at a time: closing one shows the next (the bar says how many more there
;; are). Meanwhile they take the place of the header line's usual content (e.g.
;; the sticky header), which comes back once they're all closed.
;; From code: (+my/banner-show ID TEXT :type 'warning :actions '(("Do" . fn)));
;; M-x +my/banner-close closes the one shown.
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
COLOUR a theme colour (`doom-color'): the icon's, and the bar's tint.")

(defface +my/banner-info '((t :inherit header-line)) "An info notice's bar.")

(defface +my/banner-warning '((t :inherit header-line)) "A warning notice's bar.")

(defface +my/banner-error '((t :inherit header-line)) "An error notice's bar.")

(defface +my/banner-action '((t :inherit link :underline nil :weight bold))
  "The actions in the bar.")

;; ====== CODE ======

(defvar-local +my/banner--list nil
  "The buffer's notices, the one shown first: (ID TEXT ACTIONS TYPE).")

(defvar-local +my/banner--saved-header nil
  "`header-line-format' before the notices took its place.")

(defconst +my/banner--header '(:eval (+my/banner--header-line)))

(cl-defun +my/banner-show (id text &key (type 'info) actions)
  "Show notice ID in the current buffer's bar: TEXT, of TYPE (info, warning,
error; see `+my/banner-types'), then ACTIONS to click, a list of (LABEL .
FUNCTION), FUNCTION called in the buffer. Showing ID again replaces it."
  (setq +my/banner--list (append (cl-remove id +my/banner--list :key #'car)
                                 (list (list id text actions type))))
  (unless (eq header-line-format +my/banner--header)
    (setq +my/banner--saved-header header-line-format)
    (setq-local header-line-format +my/banner--header))
  (force-mode-line-update))

(defun +my/banner-close (&optional id)
  "Close notice ID, by default the one shown."
  (interactive)
  (setq +my/banner--list (if id
                             (cl-remove id +my/banner--list :key #'car)
                           (cdr +my/banner--list)))
  (when (and (null +my/banner--list) (eq header-line-format +my/banner--header))
    (setq-local header-line-format +my/banner--saved-header))
  (force-mode-line-update))

(defun +my/banner--face (type)
  (intern (format "+my/banner-%s" (if (assq type +my/banner-types) type 'info))))

(defun +my/banner--button (label function face &optional help)
  "LABEL in the bar (of FACE), clickable: calls FUNCTION in the buffer."
  (let ((buffer (current-buffer))
        (map (make-sparse-keymap)))
    (define-key map [header-line mouse-1]
                (lambda () (interactive)
                  (when (buffer-live-p buffer)
                    (with-current-buffer buffer (funcall function)))))
    (propertize label
                'face `(+my/banner-action ,face)
                'mouse-face 'highlight
                'pointer 'hand
                'help-echo (or help (concat "mouse-1: " (string-trim label)))
                'local-map map)))

(defun +my/banner--icon (type face)
  "TYPE's icon, in its colour on the bar's FACE."
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

(defun +my/banner--header-line ()
  "The bar: the first notice, else the header line it replaced."
  (if-let* ((notice (car +my/banner--list)))
      (pcase-let* ((`(,id ,text ,actions ,type) notice)
                   (face (+my/banner--face type)))
        (concat
         (propertize "  " 'face face)
         (+my/banner--icon type face)
         (propertize (concat "  " text) 'face face)
         (mapconcat (lambda (action)
                      (concat (propertize "    " 'face face)
                              (+my/banner--button (car action) (cdr action) face)))
                    actions "")
         (when-let* ((more (length (cdr +my/banner--list)))
                     ((> more 0)))
           (propertize (format "    (%d more)" more) 'face `(shadow ,face)))
         (propertize " " 'face face 'display '(space :align-to (- right 4)))
         (+my/banner--button " ✕ " (lambda () (+my/banner-close id)) face "mouse-1: close")
         ;; To the window's edge: over the right margin (the stripe) and
         ;; fringe too, else they keep the header line's own colour.
         (propertize " " 'face face
                     'display '(space :align-to (+ right right-margin right-fringe)))))
    +my/banner--saved-header))

(defun +my/banner-faces-h ()
  "Each type's bar tinted with its theme colour, like IntelliJ's notices."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (face-background 'default nil t)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (pcase-dolist (`(,type ,_ ,colour) +my/banner-types)
          (when-let* ((tint (doom-color colour))
                      ((stringp tint)))
            (set-face-attribute (+my/banner--face type) nil
                                :inherit 'header-line
                                :background (doom-blend tint bg 0.2)
                                :foreground (face-foreground 'default nil t))))))))

(+my/banner-faces-h)

(add-hook 'doom-load-theme-hook #'+my/banner-faces-h)

;;; Notice (warning): long lines aren't wrapped

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
  ;; Not `so-long-revert': Doom's action keeps what to undo in a buffer-local
  ;; variable that entering `so-long-mode' wipes, so it did nothing.
  (so-long-mode-revert))

(add-hook 'so-long-hook #'+my/banner-long-lines-h)
