;;; $DOOMDIR/config/cheatsheet.el -*- lexical-binding: t; -*-
;; Tips panel under treemacs. Loaded from config.el.

;; ====== VARIABLES ======

;; CHEATSHEET
;; A small panel below treemacs, whenever treemacs is open, showing a few tips
;; from cheatsheet.org (Vim, Doom and this config's keys): a couple per section,
;; changing every few minutes, so over time you see them all. In the panel: n
;; shows the next tips, e opens the whole cheatsheet, q hides the panel; SPC t ?
;; hides/shows it. Edit cheatsheet.org to change the tips (reloaded on save).
(defvar +my/cheatsheet-file (expand-file-name "cheatsheet.org" doom-user-dir))

(defvar +my/cheatsheet-tips-per-section 2
  "How many tips of each section the panel shows at a time.")

(defvar +my/cheatsheet-rotate-seconds 300
  "Show the next tips this often (seconds).")

(defvar +my/cheatsheet-enabled t
  "Show the panel under treemacs.")

(defvar +my/cheatsheet--buffer-name " *Cheatsheet*") ; leading space: not in buffer lists

(defvar +my/cheatsheet--sections nil
  "The tips of `+my/cheatsheet-file', shuffled: ((SECTION . TIPS) ...).")

(defvar +my/cheatsheet--modtime nil "Modification time of the parsed file.")

(defvar +my/cheatsheet--offset 0 "Index of the first tip shown in each section.")

(defvar +my/cheatsheet--sync-timer nil)

(defvar +my/cheatsheet--rotate-timer nil)

(defvar +my/cheatsheet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "n" #'+my/cheatsheet-next)
    (define-key map "e" #'+my/cheatsheet-edit)
    (define-key map "q" #'+my/cheatsheet-toggle)
    map)
  "Keys in the tips panel (Emacs state there, so these aren't Vim's n/e/q).")

(after! winum
  (add-to-list 'winum-ignored-buffers +my/cheatsheet--buffer-name)) ; no window number

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cheatsheet panel" "t ?" #'+my/cheatsheet-toggle)

;; ====== CODE ======

(defun +my/cheatsheet--shuffle (list)
  "Return LIST in random order."
  (let ((v (vconcat list)))
    (cl-loop for i from (1- (length v)) downto 1
             do (cl-rotatef (aref v i) (aref v (random (1+ i)))))
    (append v nil)))

(defun +my/cheatsheet--parse ()
  "The tips of `+my/cheatsheet-file': its \"- \" lines under each top heading."
  (when (file-exists-p +my/cheatsheet-file)
    (with-temp-buffer
      (insert-file-contents +my/cheatsheet-file)
      (let (sections)
        (dolist (line (split-string (buffer-string) "\n"))
          (cond ((string-match "\\`\\* \\(.+\\)" line)
                 (push (list (string-trim (match-string 1 line))) sections))
                ((and sections (string-match "\\`- \\(.+\\)" line))
                 (push (string-trim (match-string 1 line)) (cdar sections)))))
        (mapcar (lambda (section)
                  (cons (car section) (+my/cheatsheet--shuffle (cdr section))))
                (nreverse sections))))))

(defun +my/cheatsheet--ensure-parsed ()
  "Parse the file again when it changed."
  (let ((modtime (file-attribute-modification-time
                  (file-attributes +my/cheatsheet-file))))
    (unless (and +my/cheatsheet--sections (equal modtime +my/cheatsheet--modtime))
      (setq +my/cheatsheet--sections (+my/cheatsheet--parse)
            +my/cheatsheet--modtime modtime
            +my/cheatsheet--offset 0))))

(defun +my/cheatsheet--format-tip (tip)
  "TIP with its =keys= (or ~keys~) drawn like key bindings in Emacs help."
  (replace-regexp-in-string
   "=[^= ][^=]*?=\\|~[^~ ][^~]*?~"      ; =SPC c ~= and ~z=~ both work
   (lambda (match)
     (propertize (substring match 1 -1) 'face 'help-key-binding))
   tip t t))

(define-derived-mode +my/cheatsheet-mode special-mode "Tips"
  "The tips panel under treemacs."
  (setq-local mode-line-format nil
              tab-line-format nil         ; no tab bar row
              cursor-type nil
              truncate-lines t
              header-line-format (propertize " Tips · n next · e all · q hide" 'face 'shadow)))

(after! evil
  (evil-set-initial-state '+my/cheatsheet-mode 'emacs))

(defun +my/cheatsheet--buffer ()
  "The panel buffer, filled with the current tips."
  (+my/cheatsheet--ensure-parsed)
  (with-current-buffer (get-buffer-create +my/cheatsheet--buffer-name)
    (unless (derived-mode-p '+my/cheatsheet-mode)
      (+my/cheatsheet-mode))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (section +my/cheatsheet--sections)
        (when-let* ((tips (cdr section)))
          (insert (propertize (car section) 'face '(:inherit shadow :weight bold)) "\n")
          (dotimes (i (min +my/cheatsheet-tips-per-section (length tips)))
            (insert " " (+my/cheatsheet--format-tip
                         (nth (mod (+ +my/cheatsheet--offset i) (length tips)) tips))
                    "\n"))))
      (when (eq (char-before) ?\n) (delete-char -1))
      (goto-char (point-min)))
    (current-buffer)))

(defun +my/cheatsheet--window ()
  (get-buffer-window +my/cheatsheet--buffer-name))

(defun +my/cheatsheet--fit ()
  "Make the panel exactly as tall as its tips."
  (when-let* ((window (+my/cheatsheet--window)))
    (let ((window-size-fixed nil))
      (fit-window-to-buffer window))))

(defun +my/cheatsheet--show ()
  "Show the panel below treemacs (a left side window in the slot after it)."
  (unless (+my/cheatsheet--window)
    (let ((window (display-buffer-in-side-window
                   (+my/cheatsheet--buffer)
                   '((side . left)
                     (slot . 1)
                     (window-height . fit-window-to-buffer)
                     (preserve-size . (nil . t))
                     (window-parameters . ((no-other-window . t)
                                           (no-delete-other-windows . t)))))))
      (when window (set-window-dedicated-p window t))
      window)))

(defun +my/cheatsheet--hide ()
  (when-let* ((window (+my/cheatsheet--window)))
    (delete-window window)))

(defun +my/cheatsheet--sync ()
  "Show the panel while treemacs is visible (and the panel is on), else hide it."
  (setq +my/cheatsheet--sync-timer nil)
  (if (and +my/cheatsheet-enabled
           (fboundp 'treemacs-get-local-window)
           (treemacs-get-local-window))
      (+my/cheatsheet--show)
    (+my/cheatsheet--hide)))

(defun +my/cheatsheet--schedule-sync (&rest _)
  "Sync after the current command (not while windows are being changed)."
  (unless (timerp +my/cheatsheet--sync-timer)
    (setq +my/cheatsheet--sync-timer (run-at-time 0 nil #'+my/cheatsheet--sync))))

(add-hook 'window-configuration-change-hook #'+my/cheatsheet--schedule-sync)

(defun +my/cheatsheet-next ()
  "Show the next tips."
  (interactive)
  (setq +my/cheatsheet--offset (+ +my/cheatsheet--offset +my/cheatsheet-tips-per-section))
  (+my/cheatsheet--buffer)
  (+my/cheatsheet--fit))

(defun +my/cheatsheet--rotate ()
  "Timer: show the next tips if the panel is visible."
  (when (+my/cheatsheet--window)
    (+my/cheatsheet-next)))

(unless (timerp +my/cheatsheet--rotate-timer)
  (setq +my/cheatsheet--rotate-timer
        (run-with-timer +my/cheatsheet-rotate-seconds +my/cheatsheet-rotate-seconds
                        #'+my/cheatsheet--rotate)))

(defun +my/cheatsheet-toggle ()
  "Hide or show the tips panel under treemacs."
  (interactive)
  (setq +my/cheatsheet-enabled (not +my/cheatsheet-enabled))
  (+my/cheatsheet--sync)
  (message (cond ((not +my/cheatsheet-enabled) "Tips hidden (SPC t ? shows them)")
                 ((+my/cheatsheet--window) "Tips shown")
                 (t "Tips on: they show under treemacs (SPC o p)"))))

(defun +my/cheatsheet-edit ()
  "Open the whole cheatsheet."
  (interactive)
  (if (window-dedicated-p)              ; from the panel: open it in a main window
      (progn (select-window (get-mru-window nil nil t))
             (find-file +my/cheatsheet-file))
    (find-file +my/cheatsheet-file)))

(defun +my/cheatsheet--after-save-h ()
  "Show the new tips when the cheatsheet file is saved."
  (when (and buffer-file-name (file-equal-p buffer-file-name +my/cheatsheet-file))
    (+my/cheatsheet--buffer)
    (+my/cheatsheet--fit)))

(add-hook 'after-save-hook #'+my/cheatsheet--after-save-h)
