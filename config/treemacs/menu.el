;;; $DOOMDIR/config/treemacs/menu.el -*- lexical-binding: t; -*-
;; The sidebar's context menu (a right click). Loaded from config/treemacs.el.

;; REVEAL IN FINDER
;; After "Open With", on a file or a folder: it shown selected in the file
;; manager (Finder; on Linux the file manager, config/os.el).
(defun +my/treemacs-reveal-in-finder ()
  "The file or folder at point shown selected in the file manager (Finder on
macOS)."
  (interactive)
  (let ((path (ignore-errors (treemacs--prop-at-point :path))))
    (unless (stringp path)
      (user-error "Not a file or a folder"))
    (+my/os-reveal path)))

(defun +my/treemacs--reveal-label ()
  "The menu item's name: \"Reveal in Finder\" (macOS), \"Show in File
Manager\"."
  (if (+my/macos-p) "Reveal in Finder" "Show in File Manager"))

(defun +my/treemacs--menu-with-reveal (items)
  "The menu's ITEMS with \"Reveal in Finder\" after \"Open With\" (shown on a
file or a folder); ITEMS unchanged without \"Open With\" (its submenus)."
  (let ((open-with (seq-position items "Open With"
                                 (lambda (item name) (equal (car-safe item) name)))))
    (if (not open-with)
        items
      (append (seq-take items (1+ open-with))
              `([,(+my/treemacs--reveal-label)
                 +my/treemacs-reveal-in-finder
                 :visible ,(stringp (ignore-errors (treemacs--prop-at-point :path)))])
              (seq-drop items (1+ open-with))))))

;; treemacs builds the menu anew on each click, from a fixed list: the item
;; added to that list as it's made.
(defadvice! +my/treemacs-menu-reveal-a (fn &rest args)
  :around #'treemacs-rightclick-menu
  (let ((create (symbol-function 'easy-menu-create-menu)))
    (cl-letf (((symbol-function 'easy-menu-create-menu)
               (lambda (name items &rest rest)
                 (apply create name (+my/treemacs--menu-with-reveal items) rest))))
      (apply fn args))))
