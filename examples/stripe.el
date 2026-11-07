;;; $DOOMDIR/examples/stripe.el -*- lexical-binding: t; -*-
;; Example: the error stripe (config/stripe.el, docs/editor.md). M-x
;; +my/example-stripe makes a Git repository in the temp folder with an Emacs
;; Lisp file, inventory.el, long enough to scroll, committed and then changed
;; (lines changed, added and removed: the git gutter's colours) with mistakes
;; the byte compiler finds (flycheck: errors in red, warnings in yellow), and
;; opens it. The strip at the window's right edge maps them all onto its
;; height, the part on screen a light band: click it to jump there, drag the
;; band to scroll. The repository is deleted once the file is closed.

;; ====== VARIABLES ======

(defconst +my/example-stripe--kinds
  '("apple" "pear" "plum" "cherry" "grape" "lemon" "lime" "orange" "peach"
    "apricot" "banana" "mango" "melon" "kiwi" "fig" "date" "olive" "quince"
    "berry" "currant" "guava" "papaya" "lychee" "coconut")
  "The inventory's kinds of fruit: a few functions each.")

;; ====== CODE ======

(defun +my/example-stripe--kind (kind)
  "KIND's functions."
  (format "(defun inventory-%s-count (items)
  \"How many %ss there are in ITEMS.\"
  (seq-count (lambda (item) (equal (inventory-item-kind item) \"%s\")) items))

(defun inventory-%s-value (items)
  \"What ITEMS' %ss are worth.\"
  (inventory-price (seq-filter (lambda (item) (equal (inventory-item-kind item) \"%s\")) items)
                   inventory-%s-price))

" kind kind kind kind kind kind kind))

(defun +my/example-stripe--text (changed)
  "inventory.el, as committed, or CHANGED since (see above)."
  (let ((kinds +my/example-stripe--kinds))
    (concat
     ";;; inventory.el --- A fruit shop's inventory -*- lexical-binding: t; -*-

;;; Commentary:
;; How many of each fruit, and what they're worth.

;;; Code:

(require 'seq)

(defmacro inventory-define-unit (name factor)
  \"Define unit NAME, FACTOR pieces (a positive number).\"
  (unless (and (numberp factor) (> factor 0))
    (error \"Unit %s: its factor must be a positive number, not %S\" name factor))
  `(defconst ,(intern (format \"inventory-unit-%s\" name)) ,factor))

(inventory-define-unit dozen 12)
(inventory-define-unit crate 24)

(defun inventory-item-kind (item)
  \"ITEM's kind of fruit.\"
  (car item))

(defun inventory-price (items price)
  \"ITEMS, PRICE each.\"
  (* (length items) price))

(defun inventory-total ()
  \"All the inventory is worth.\"
  (+ inventory-cache 0))

"
     (mapconcat (lambda (kind) (format "(defconst inventory-%s-price 1 \"A %s's price.\")\n" kind kind))
                kinds "")
     "\n"
     (mapconcat
      (lambda (kind)
        (let ((text (+my/example-stripe--kind kind)))
          (cond
           ;; Changed: a docstring reworded.
           ((and changed (equal kind "cherry"))
            (replace-regexp-in-string "How many cherrys there are" "The number of cherries" text t t))
           ;; Removed since.
           ((and changed (equal kind "mango")) "")
           ;; Added since: a function, with a mistake.
           ((and changed (equal kind "kiwi"))
            (concat text "(defun inventory-kiwi-report (items)
  \"A line about ITEMS' kiwis.\"
  (let ((total 0))
    (format \"%d kiwis\" (inventory-kiwi-count items))))

(defun inventory-kiwi-worth (items)
  \"ITEMS' kiwis' worth, rounded.\"
  (round (inventory-price items)))

"))
           ;; Mistakes further down: a function given too few arguments;
           ;; last (the compiler stops at an error: it'd hide the warnings
           ;; after it), a unit that isn't a number.
           ((and changed (equal kind "guava"))
            (concat text "(defun inventory-guava-share (items)
  \"ITEMS' guavas, out of all of them.\"
  (/ (inventory-guava-count items) (inventory-price items)))

"))
           ((and changed (equal kind "coconut"))
            (concat text "(inventory-define-unit tray \"six\")\n\n"))
           (t text))))
      kinds "")
     "(provide 'inventory)
;;; inventory.el ends here
")))

(defun +my/example-stripe--git (&rest args)
  "Run git with ARGS in the current folder, as no one in particular (not
your name, hooks or signing): its exit status."
  (let ((process-environment (append '("GIT_EDITOR=true" "GIT_TERMINAL_PROMPT=0")
                                     process-environment)))
    (apply #'call-process "git" nil nil nil
           "-c" "user.name=Example" "-c" "user.email=example@example.invalid"
           "-c" "commit.gpgsign=false" "-c" "core.hooksPath=/dev/null"
           "-c" "init.defaultBranch=main"
           args)))

(defun +my/example-stripe--repo ()
  "A repository in the temp folder: inventory.el committed, then changed
(see above). Its folder."
  (let ((default-directory (+my/example-folder "stripe")))
    (+my/example-stripe--git "init" "-q")
    (+my/example-write default-directory "inventory.el" (+my/example-stripe--text nil))
    (unless (and (zerop (+my/example-stripe--git "add" "inventory.el"))
                 (zerop (+my/example-stripe--git "commit" "-qm" "Inventory")))
      (error "Example: git commit failed"))
    (+my/example-write default-directory "inventory.el" (+my/example-stripe--text t))
    default-directory))

(defun +my/example-stripe ()
  "Example: the error stripe of a file with errors, warnings and git changes,
in a temp repository (deleted once closed). See examples/stripe.el."
  (interactive)
  (let ((repo (+my/example-stripe--repo)))
    ;; Flycheck byte-compiles Emacs Lisp only in files trusted (Emacs 30:
    ;; compiling expands macros, which can run code): the example's own,
    ;; written here, while it's open.
    (when (and (boundp 'trusted-content) (listp trusted-content))
      (push repo trusted-content))
    (delete-other-windows)
    (find-file (expand-file-name "inventory.el" repo))
    ;; What the strip shows: flycheck's findings and git's changes (on where
    ;; Doom turns them on; here for sure).
    (when (require 'flycheck nil t)
      (flycheck-mode 1)
      (flycheck-buffer))
    (when (require 'diff-hl nil t)
      (diff-hl-mode 1)
      (diff-hl-update))
    (when (and (fboundp '+my/stripe-mode) (not (bound-and-true-p +my/stripe-mode)))
      (+my/stripe-mode 1))
    ;; Where lines were removed and added, with warnings: the gutter and the
    ;; strip both have something to show.
    (goto-char (point-min))
    (when (search-forward "(defun inventory-kiwi-report" nil t)
      (forward-line 0)
      (when-let* ((window (get-buffer-window (current-buffer))))
        (set-window-start window (save-excursion (forward-line -12) (point)))))
    (+my/example-delete-when-closed
     repo (list (current-buffer))
     (lambda ()
       (when (boundp 'trusted-content)
         (setq trusted-content (if (listp trusted-content) (delete repo trusted-content) trusted-content)))))
    (message "Stripe example: errors red, warnings yellow, git's changes in the gutter's colours; click the strip to jump, drag its band to scroll")
    (current-buffer)))

(defun +my/example-stripe-ready ()
  "Non-nil once the example's strip shows flycheck's findings and git's
changes."
  (when-let* ((buffer (seq-find (lambda (buffer)
                                  (equal (buffer-local-value 'buffer-file-name buffer)
                                         (and (buffer-local-value '+my/example--closing buffer)
                                              (expand-file-name "inventory.el"
                                                                (car (buffer-local-value '+my/example--closing buffer))))))
                                (buffer-list))))
    (with-current-buffer buffer
      (and (bound-and-true-p flycheck-mode)
           (eq (bound-and-true-p flycheck-last-status-change) 'finished)
           (flycheck-has-current-errors-p)
           (seq-some (lambda (ov) (overlay-get ov 'diff-hl))
                     (overlays-in (point-min) (point-max)))))))

(provide 'example-stripe)
