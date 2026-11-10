;;; $DOOMDIR/config/agent-shell/excalidraw.el -*- lexical-binding: t; -*-
;; Drawings for Claude: drawn in Excalidraw, inserted into an agent-shell
;; prompt as images (see DRAWINGS FOR CLAUDE there). Loaded from
;; config/agent-shell.el.

(defvar-local +my/agent-shell-excalidraw--shell nil
  "In a drawing for Claude: the agent-shell buffer it goes to.")

(defvar-local +my/agent-shell-excalidraw--earlier nil
  "In a drawing for Claude: the earlier drawing shown instead of its own (M-p,
M-n), as (POSITION . OWN-TEXT); nil: its own.")

(define-minor-mode +my/agent-shell-excalidraw-mode
  "A drawing for Claude, inserted into an agent-shell prompt (see DRAWINGS FOR
CLAUDE in config/agent-shell.el).

\\{+my/agent-shell-excalidraw-mode-map}"
  :lighter " Claude"
  (if +my/agent-shell-excalidraw-mode
      (+my/agent-shell-excalidraw--notice)
    (when (fboundp '+my/banner-close)
      (+my/banner-close 'agent-shell-excalidraw))))

(defun +my/agent-shell-excalidraw--notice ()
  "Say at the drawing's top what its keys do, with buttons."
  (when (fboundp '+my/banner-show)
    (+my/banner-show
     'agent-shell-excalidraw
     (substitute-command-keys
      "\\<+my/agent-shell-excalidraw-mode-map>Drawing for Claude: \
\\[+my/agent-shell-excalidraw-insert] inserts it into the prompt, \
\\[+my/agent-shell-excalidraw-discard] discards it, \
\\[+my/agent-shell-excalidraw-previous] / \\[+my/agent-shell-excalidraw-next] \
earlier drawings")
     :actions '(("Insert into the prompt" . +my/agent-shell-excalidraw-insert)
                ("Discard" . +my/agent-shell-excalidraw-discard)))))

;; FILES

(defun +my/agent-shell-excalidraw--new-file (dir)
  "A new drawing's file in DIR, named by the time: drawing-2026-11-07-13-05-09
.excalidraw.svg (-2, -3... if taken)."
  (let* ((base (format-time-string "drawing-%Y-%m-%d-%H-%M-%S"))
         (n 1)
         file)
    (while (file-exists-p
            (setq file (expand-file-name
                        (concat base (if (= n 1) "" (format "-%d" n)) ".excalidraw.svg")
                        dir)))
      (setq n (1+ n)))
    file))

(defun +my/agent-shell-excalidraw--png-file (file)
  "Drawing FILE's PNG: beside it, its name with .png for .excalidraw.svg."
  (concat (string-remove-suffix ".excalidraw.svg" file) ".png"))

(defun +my/agent-shell-excalidraw--earlier-files ()
  "The drawing's folder's other drawings, newest first (named by the time).
Itself left out by its true name: `file-equal-p' compares every attribute,
its access time too, so a read of it meanwhile (Spotlight indexing it) had
it listed among its own earlier drawings."
  (when buffer-file-name
    (let ((dir (file-name-directory buffer-file-name))
          (own (file-truename buffer-file-name)))
      (sort (seq-remove (lambda (file) (equal (file-truename file) own))
                        (directory-files dir t "\\.excalidraw\\.svg\\'"))
            (lambda (a b) (string> (file-name-nondirectory a) (file-name-nondirectory b)))))))

;; STARTING

(defun +my/agent-shell-excalidraw--shell-here ()
  "The agent-shell to draw for: this buffer, else the one agent-shell picks."
  (cond ((derived-mode-p 'agent-shell-mode) (current-buffer))
        ((fboundp 'agent-shell--shell-buffer)
         (ignore-errors (agent-shell--shell-buffer :no-create t)))))

(defun +my/agent-shell-excalidraw--where (shell)
  "Where a drawing for SHELL shows (a `display-buffer' action): in the window
left of SHELL's, which shows its own buffer again once the drawing closes;
without one, in a new window split off to its left."
  (let ((window (or (get-buffer-window shell) (selected-window))))
    `((display-buffer-in-previous-window display-buffer-in-direction)
      (previous-window . ,(window-in-direction 'left window))
      (direction . left)
      (window . ,window))))

(defun +my/agent-shell-excalidraw ()
  "Draw for Claude: a new drawing on the left, inserted into this
agent-shell's prompt with \\<+my/agent-shell-excalidraw-mode-map>\\[+my/agent-shell-excalidraw-insert] \
\(see DRAWINGS FOR CLAUDE in config/agent-shell.el)."
  (interactive)
  (let ((shell (+my/agent-shell-excalidraw--shell-here)))
    (unless (buffer-live-p shell)
      (user-error "No agent-shell to draw for: SPC o c starts one"))
    (unless (and (+my/webkit-p) (+my/excalidraw-ensure))
      (user-error "Drawings need Excalidraw, in a GUI Emacs with xwidgets"))
    (let* ((dir (with-current-buffer shell
                  (agent-shell--dot-subdir +my/agent-shell-drawings-subdir)))
           (buffer (+my/excalidraw-open (+my/agent-shell-excalidraw--new-file dir) t
                                        (+my/agent-shell-excalidraw--where shell))))
      (with-current-buffer buffer
        (setq +my/agent-shell-excalidraw--shell shell
              +my/agent-shell-excalidraw--earlier nil)
        (+my/agent-shell-excalidraw-mode 1))
      buffer)))

;; INSERTING, DISCARDING

(defun +my/agent-shell-excalidraw--close (buffer)
  "Close drawing BUFFER, unsaved changes dropped, and the window opened for
it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (set-buffer-modified-p nil))
    (if-let* ((window (get-buffer-window buffer)))
        (quit-window t window)
      (kill-buffer buffer))))

(defun +my/agent-shell-excalidraw-insert ()
  "Insert the drawing into its agent-shell's prompt, as an image (see
DRAWINGS FOR CLAUDE in config/agent-shell.el), and close it."
  (interactive)
  (unless +my/agent-shell-excalidraw-mode
    (user-error "Not a drawing for Claude"))
  (let ((shell +my/agent-shell-excalidraw--shell)
        (drawing (current-buffer)))
    (unless (buffer-live-p shell)
      (user-error "Its agent-shell is gone"))
    (when (buffer-modified-p)
      (save-buffer))
    (let ((png (+my/excalidraw-png (+my/agent-shell-excalidraw--png-file buffer-file-name))))
      (+my/agent-shell-excalidraw--close drawing)
      (with-current-buffer shell
        (agent-shell-insert :text (agent-shell--get-files-context :files (list png))
                            :shell-buffer shell))
      png)))

(defun +my/agent-shell-excalidraw-discard ()
  "Close the drawing without inserting it; its files are deleted."
  (interactive)
  (unless +my/agent-shell-excalidraw-mode
    (user-error "Not a drawing for Claude"))
  (let ((file buffer-file-name))
    (+my/agent-shell-excalidraw--close (current-buffer))
    (when file
      (dolist (gone (list file (+my/agent-shell-excalidraw--png-file file)))
        (when (file-exists-p gone)
          (delete-file gone))))))

;; EARLIER DRAWINGS

(defun +my/agent-shell-excalidraw--step (step)
  "Show the earlier drawing STEP away (1: older, -1: newer); past the newest,
the drawing's own again."
  (unless +my/agent-shell-excalidraw-mode
    (user-error "Not a drawing for Claude"))
  (let* ((files (+my/agent-shell-excalidraw--earlier-files))
         (position (car +my/agent-shell-excalidraw--earlier))
         (next (if position (+ position step) (if (> step 0) 0 -1))))
    (cond ((null files) (user-error "No earlier drawings"))
          ((>= next (length files)) (user-error "No older drawing"))
          ((< next 0)
           (unless position
             (user-error "No newer drawing"))
           (+my/excalidraw-replace (cdr +my/agent-shell-excalidraw--earlier))
           (setq +my/agent-shell-excalidraw--earlier nil)
           (message "This drawing again"))
          (t
           (let ((own (if position
                          (cdr +my/agent-shell-excalidraw--earlier)
                        (buffer-substring-no-properties (point-min) (point-max))))
                 (file (nth next files)))
             (+my/excalidraw-replace (with-temp-buffer
                                       (insert-file-contents file)
                                       (buffer-string)))
             (setq +my/agent-shell-excalidraw--earlier (cons next own))
             (message "Earlier drawing %d of %d: %s" (1+ next) (length files)
                      (file-name-nondirectory file)))))))

(defun +my/agent-shell-excalidraw-previous ()
  "An older drawing instead of this one (see DRAWINGS FOR CLAUDE in
config/agent-shell.el)."
  (interactive)
  (+my/agent-shell-excalidraw--step 1))

(defun +my/agent-shell-excalidraw-next ()
  "A newer drawing instead of this one; past the newest, this one again."
  (interactive)
  (+my/agent-shell-excalidraw--step -1))
