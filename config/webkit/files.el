;;; $DOOMDIR/config/webkit/files.el -*- lexical-binding: t; -*-
;; Files as URLs, downloads, the buffer's text. Loaded from config/webkit.el.

(defun +my/webkit-file-url (file)
  "FILE's file:// URL. Spaces and such encoded: Emacs's macOS WebKit doesn't
check that a URL is valid. A `%' too: in a file's name it's not an escape
(\"a%20b.pdf\" isn't \"a b.pdf\")."
  (require 'url-util)
  (let ((allowed (copy-sequence url-path-allowed-chars)))
    (aset allowed ?% nil)
    (concat "file://" (url-hexify-string (expand-file-name file) allowed))))

(defun +my/webkit-url-file (url)
  "The file a file:// URL names (without its #fragment)."
  (require 'url-parse)
  (decode-coding-string (url-unhex-string (url-filename (url-generic-parse-url url)))
                        'utf-8))

;; THE BUFFER'S TEXT
;; The views are shown over all of the buffer's text (point kept at its
;; start): a page whose buffer visits a file it edits (a drawing, see
;; config/excalidraw.el) puts the file's new text there, to be saved as any.
(defun +my/webkit-set-text (text)
  "Make TEXT (not empty) the buffer's text, under its views (see above); the
buffer is then modified."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert text)
    (goto-char (point-min))
    (put-text-property (point-min) (point-max) 'display "")
    (when +my/webkit--pointer
      (put-text-property (point-min) (point-max) 'pointer +my/webkit--pointer))
    ;; Emptied, the views' overlays were left with nothing in them.
    (dolist (view +my/webkit--views)
      (when (overlay-buffer view)
        (move-overlay view (point-min) (point-max))))
    (dolist (window (get-buffer-window-list nil 'nomini t))
      (set-window-point window (point-min))
      (set-window-start window (point-min) t))))

;; DOWNLOADS
;; What a page needs (a library's files) is downloaded once, each file checked
;; against its SHA-256.
(defun +my/webkit-installed-p (files dir)
  "Non-nil if FILES, ((FILE URL SHA256)...), are all in DIR."
  (seq-every-p (lambda (file) (file-exists-p (expand-file-name (car file) dir)))
               files))

(defun +my/webkit-install (name version files dir)
  "Download NAME's VERSION into DIR: FILES, ((FILE URL SHA256)...), FILE in
DIR (in folders of its own maybe) from URL, checked against its SHA-256."
  (require 'url)
  (pcase-dolist (`(,path ,url ,sha256) files)
    (let* ((file (expand-file-name path dir))
           (part (concat file ".part")))
      (make-directory (file-name-directory file) t)
      (message "Downloading %s: %s..." name path)
      (url-copy-file url part t)
      (unless (equal (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally part)
                       (secure-hash 'sha256 (current-buffer)))
                     sha256)
        (delete-file part)
        (error "%s: %s isn't the file expected (SHA-256 differs), not installed" name url))
      (rename-file part file t)))
  (message "%s %s installed in %s" name version dir))
