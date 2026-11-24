;;; $DOOMDIR/config/agent-shell/excalidraw.el -*- lexical-binding: t; -*-
;; Drawings for the agent: drawn in Excalidraw, inserted into an agent-shell
;; prompt as images (see DRAWINGS FOR THE AGENT there). Loaded from
;; config/agent-shell.el.

(defvar-local +my/agent-shell-excalidraw--shell nil
  "In a drawing for the agent: the agent-shell buffer it goes to.")

(defvar-local +my/agent-shell-excalidraw--earlier nil
  "In a drawing for the agent: the earlier drawing shown instead of its own (M-p,
M-n), as (POSITION . OWN-TEXT); nil: its own.")

(defvar-local +my/agent-shell-excalidraw--inserted nil
  "In a drawing for the agent: non-nil once inserted (its file kept, blank or not).")

(define-minor-mode +my/agent-shell-excalidraw-mode
  "A drawing for the agent, inserted into an agent-shell prompt (see DRAWINGS FOR
THE AGENT in config/agent-shell.el).

\\{+my/agent-shell-excalidraw-mode-map}"
  :lighter " Agent"
  (if +my/agent-shell-excalidraw-mode
      (progn
        (+my/agent-shell-excalidraw--notice)
        (add-hook 'kill-buffer-hook #'+my/agent-shell-excalidraw--killed-h nil t))
    (remove-hook 'kill-buffer-hook #'+my/agent-shell-excalidraw--killed-h t)
    (when (fboundp '+my/banner-close)
      (+my/banner-close 'agent-shell-excalidraw))))

(defun +my/agent-shell-excalidraw--notice ()
  "Say at the drawing's top what its keys do, with buttons. Short: the keys
fit beside the buttons in a pane of 70 columns (it opens in half a frame),
the buttons whole at 40."
  (when (fboundp '+my/banner-show)
    (+my/banner-show
     'agent-shell-excalidraw
     (substitute-command-keys
      "\\<+my/agent-shell-excalidraw-mode-map>Drawing: \
\\[+my/agent-shell-excalidraw-insert] inserts, \
\\[+my/agent-shell-excalidraw-discard] discards, \
\\[+my/agent-shell-excalidraw-previous] / \\[+my/agent-shell-excalidraw-next] \
earlier drawings")
     :actions '(("Insert" . +my/agent-shell-excalidraw-insert)
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

(defun +my/agent-shell-excalidraw--blank-p (file)
  "Non-nil if nothing is drawn in drawing FILE, an .excalidraw.svg: the scene
Excalidraw keeps in it (between payload-start and payload-end, base64 JSON
whose \"encoded\", zlib's if \"compressed\", holds the scene's JSON as
bytes) has no elements but deleted ones. Nil if it can't tell."
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents-literally file)
      (goto-char (point-min))
      (when (re-search-forward "<!-- payload-start -->\\([^<]*\\)<!-- payload-end -->" nil t)
        (let* ((payload (json-parse-string
                         (decode-coding-string (base64-decode-string (match-string 1)) 'latin-1)
                         :object-type 'alist :false-object nil))
               (scene (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert (encode-coding-string (alist-get 'encoded payload) 'latin-1))
                        (when (alist-get 'compressed payload)
                          (unless (zlib-decompress-region (point-min) (point-max))
                            (error "Not zlib's")))
                        (json-parse-string (decode-coding-string (buffer-string) 'utf-8)
                                           :object-type 'alist :array-type 'list
                                           :false-object nil :null-object nil))))
          (seq-every-p (lambda (element) (alist-get 'isDeleted element))
                       (alist-get 'elements scene)))))))

(defun +my/agent-shell-excalidraw--earlier-files ()
  "The drawing's folder's other drawings, newest first (named by the time),
but blank ones. Itself left out by its true name: `file-equal-p' compares
every attribute, its access time too, so a read of it meanwhile (Spotlight
indexing it) had it listed among its own earlier drawings."
  (when buffer-file-name
    (let ((dir (file-name-directory buffer-file-name))
          (own (file-truename buffer-file-name)))
      (sort (seq-remove (lambda (file) (or (equal (file-truename file) own)
                                           (+my/agent-shell-excalidraw--blank-p file)))
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
  "Draw for the agent: a new drawing on the left, inserted into this
agent-shell's prompt with \\<+my/agent-shell-excalidraw-mode-map>\\[+my/agent-shell-excalidraw-insert] \
\(see DRAWINGS FOR THE AGENT in config/agent-shell.el)."
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
DRAWINGS FOR THE AGENT in config/agent-shell.el), and close it."
  (interactive)
  (unless +my/agent-shell-excalidraw-mode
    (user-error "Not a drawing for the agent"))
  (let ((shell +my/agent-shell-excalidraw--shell)
        (drawing (current-buffer)))
    (unless (buffer-live-p shell)
      (user-error "Its agent-shell is gone"))
    ;; A change made just before: not marked modified yet (see SAVING in
    ;; config/excalidraw/sync.el).
    (+my/excalidraw-flush)
    (when (buffer-modified-p)
      (save-buffer))
    (let ((png (+my/excalidraw-png (+my/agent-shell-excalidraw--png-file buffer-file-name))))
      (setq +my/agent-shell-excalidraw--inserted t)
      (+my/agent-shell-excalidraw--close drawing)
      (with-current-buffer shell
        (agent-shell-insert :text (agent-shell--get-files-context :files (list png))
                            :shell-buffer shell))
      png)))

(defun +my/agent-shell-excalidraw--killed-h ()
  "A drawing for the agent closed without being inserted (its tab, SPC b k): its
file deleted if nothing is drawn in it (it's saved blank as it opens), else
each one closed so was left for M-p to list."
  (when (and buffer-file-name
             (not +my/agent-shell-excalidraw--inserted)
             (file-exists-p buffer-file-name)
             (+my/agent-shell-excalidraw--blank-p buffer-file-name))
    (delete-file buffer-file-name)))

(defun +my/agent-shell-excalidraw-discard ()
  "Close the drawing without inserting it; its files are deleted."
  (interactive)
  (unless +my/agent-shell-excalidraw-mode
    (user-error "Not a drawing for the agent"))
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
    (user-error "Not a drawing for the agent"))
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
                        ;; With a change made just before: its export, on
                        ;; its way, would be dropped once another drawing
                        ;; is shown.
                        (+my/excalidraw-flush)
                        (buffer-substring-no-properties (point-min) (point-max))))
                 (file (nth next files)))
             (+my/excalidraw-replace (with-temp-buffer
                                       (insert-file-contents file)
                                       (buffer-string)))
             (setq +my/agent-shell-excalidraw--earlier (cons next own))
             (message "Earlier drawing %d of %d: %s" (1+ next) (length files)
                      (file-name-nondirectory file)))))))

(defun +my/agent-shell-excalidraw-previous ()
  "An older drawing instead of this one (see DRAWINGS FOR THE AGENT in
config/agent-shell.el)."
  (interactive)
  (+my/agent-shell-excalidraw--step 1))

(defun +my/agent-shell-excalidraw-next ()
  "A newer drawing instead of this one; past the newest, this one again."
  (interactive)
  (+my/agent-shell-excalidraw--step -1))
