;;; $DOOMDIR/config/banner/show.el -*- lexical-binding: t; -*-
;; Showing and closing notices. Loaded from config/banner.el.

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
