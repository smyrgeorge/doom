;;; $DOOMDIR/config/excalidraw/sync.el -*- lexical-binding: t; -*-
;; The drawing and its file in sync: saving, watching. Loaded from config/excalidraw.el.

;; SAVING

(defvar-local +my/excalidraw--error nil
  "The page's error, shown in a notice (see WATCHING).")

;; The page says in its title the drawing's version (one more at each change;
;; a new file's blank drawing is the first) and the version of its latest
;; export (the file's text as it would be saved). Emacs, every 0.1 s while
;; it's on screen (see WATCHING in config/webkit/js.el): a new version marks the
;; buffer modified; a new export is asked for (an answer awaited, see
;; JAVASCRIPT there) and becomes the buffer's text, then the other views'
;; drawing. Saving first asks each page for its version, exported now, and
;; waits for those to be in the buffer.
(defun +my/excalidraw--state (&optional xwidget)
  "XWIDGET's page's state (default: this buffer's view), a plist (:ready
:version :exported :cursor :dark :error), or nil before it has said it."
  (+my/webkit-title-json (or xwidget (+my/webkit-xwidget)) "exd "))

(defun +my/excalidraw--number (state key)
  (let ((n (plist-get state key)))
    (if (natnump n) n 0)))

(defun +my/excalidraw--sync (xwidget)
  "Take in what XWIDGET's page says (see above); return its state."
  (when-let* ((state (+my/excalidraw--state xwidget)))
    (let ((version (+my/excalidraw--number state :version))
          (exported (+my/excalidraw--number state :exported)))
      (when (> version (or (xwidget-get xwidget 'seen) 0))
        (xwidget-put xwidget 'seen version)
        (unless (buffer-modified-p)
          (set-buffer-modified-p t)))
      (when (and (> exported (or (xwidget-get xwidget 'fetched) 0))
                 (not (+my/webkit--asked-p xwidget)))
        (+my/webkit-ask "window.exd ? exd.answer() : '0\\n'" #'+my/excalidraw--received
                        xwidget))
      ;; Its library (see libraries.el).
      (when (and (> (+my/excalidraw--number state :library) (or (xwidget-get xwidget 'library) 0))
                 (not (+my/webkit--asked-p xwidget)))
        (+my/webkit-ask "window.exd ? exd.library() : '0\\n'" #'+my/excalidraw--library-received
                        xwidget)))
    state))

(defun +my/excalidraw--versioned (answer)
  "A page's ANSWER, \"VERSION\\nTEXT\", as (VERSION . TEXT); nil if it isn't one."
  (when-let* (((stringp answer))
              (newline (string-search "\n" answer))
              ((string-match-p "\\`[0-9]+\\'" (substring answer 0 newline))))
    (cons (string-to-number (substring answer 0 newline))
          (substring answer (1+ newline)))))

(defun +my/excalidraw--received (answer)
  "A page's latest export (see above): \"VERSION\\nTEXT\", TEXT the file's."
  (pcase-let* ((xwidget +my/webkit-answering)
               (`(,version . ,text) (+my/excalidraw--versioned answer)))
    (when (and xwidget version
               (eq (xwidget-buffer xwidget) (current-buffer))
               (derived-mode-p '+my/excalidraw-mode)
               (> version (or (xwidget-get xwidget 'fetched) 0)))
      (xwidget-put xwidget 'fetched version)
      (unless (or (string-empty-p text)
                  (string= text (buffer-substring-no-properties (point-min) (point-max))))
        (+my/webkit-set-text text)
        (when +my/excalidraw--dir
          (+my/excalidraw--write-page))
        (+my/excalidraw--show text xwidget)
        (when +my/excalidraw--save-new
          (setq +my/excalidraw--save-new nil)
          (run-at-time 0 nil #'+my/excalidraw--save (current-buffer)))))))

(defun +my/excalidraw--show (text &optional except)
  "Show the drawing whose file's text is TEXT in the buffer's views, but
EXCEPT's."
  (let ((script (format "window.exd && exd.replace(\"%s\")" (+my/excalidraw--base64 text))))
    (dolist (xwidget (+my/webkit-xwidgets))
      (unless (eq xwidget except)
        (+my/webkit-execute script xwidget)))))

(defun +my/excalidraw--flushed (version)
  "A page's answer to saving: the VERSION its drawing is at (see above)."
  (when +my/webkit-answering
    (xwidget-put +my/webkit-answering 'flushed
                 (if (stringp version) (string-to-number version) 0))))

(defun +my/excalidraw--in-buffer-p (xwidget)
  "Non-nil if XWIDGET's drawing, as it was when saving began, is in the
buffer (see above)."
  (+my/excalidraw--sync xwidget)
  (when-let* ((flushed (xwidget-get xwidget 'flushed)))
    (<= flushed (or (xwidget-get xwidget 'fetched) 0))))

(defun +my/excalidraw--before-save ()
  "Saving: the drawings' last changes in the buffer first (see above)."
  (when-let* ((xwidgets (+my/webkit-xwidgets)))
    (dolist (xwidget xwidgets)
      (xwidget-put xwidget 'flushed nil)
      (+my/webkit-ask "window.exd ? exd.flush() : '0'" #'+my/excalidraw--flushed xwidget))
    (unless (+my/webkit-wait (lambda () (seq-every-p #'+my/excalidraw--in-buffer-p xwidgets))
                             5)
      (message "The drawing's last change didn't come from its page: saved without it"))))

(defun +my/excalidraw--save (buffer)
  "Save BUFFER's drawing, if changed."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (buffer-modified-p)
        (let ((save-silently t))
          (save-buffer))))))

(defun +my/excalidraw--revert (_ignore-auto noconfirm)
  "Show the drawing anew from its file (asked first if it was changed here,
unless NOCONFIRM)."
  (when (and (buffer-modified-p) (not noconfirm)
             (not (yes-or-no-p (format "Discard the drawing's changes, read %s again? "
                                       (file-name-nondirectory buffer-file-name)))))
    (user-error "Not read again"))
  (let* ((file buffer-file-name)
         (text (with-temp-buffer
                 (insert-file-contents file)
                 (buffer-string))))
    ;; The file's time first: changing the text of a buffer whose file
    ;; changed asks whether to.
    (set-visited-file-modtime)
    (+my/webkit-set-text (if (string-empty-p text) " " text))
    (set-buffer-modified-p nil)
    (when +my/excalidraw--dir
      (+my/excalidraw--write-page))
    (+my/excalidraw--show text)))

;; WATCHING
;; Every 0.1 s, for each window showing a drawing, from its view's title (see
;; WATCHING in config/webkit/js.el): its changes (see SAVING), the mouse pointer
;; the page wants (the hand over buttons and what can be moved, the I-beam
;; over text, else the arrow), its error in a notice.
(defun +my/excalidraw--watch (window xwidget)
  "WINDOW shows XWIDGET's view of the drawing (see above)."
  (when-let* ((state (+my/excalidraw--sync xwidget)))
    (+my/webkit-pointer window (pcase (plist-get state :cursor)
                                 ("hand" 'hand) ("text" 'text) (_ 'arrow)))
    (+my/excalidraw--show-error (plist-get state :error))))

(defun +my/excalidraw--show-error (error)
  "Show ERROR (a string, the page's) in a notice above the drawing; nil: none."
  (unless (equal error +my/excalidraw--error)
    (setq +my/excalidraw--error error)
    (cond ((not (fboundp '+my/banner-show))
           (when error (message "%s" error)))
          (error
           (+my/banner-show 'excalidraw
                            (if (string-prefix-p "Export" error)
                                (format "The drawing can't be saved: %s" error)
                              (format "%s: shown blank, saving replaces the file with what you draw"
                                      error))
                            :type 'error))
          (t (+my/banner-close 'excalidraw)))))
