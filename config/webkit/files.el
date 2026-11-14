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
;; against its SHA-256. Emacs waits for it (the page needs it now), but C-g
;; stops it (from a timer too, where Emacs otherwise ignores it), and it gives
;; up once nothing came for `+my/webkit-download-timeout' seconds (a host it
;; can't reach: Emacs's own wait for a connection is over a minute, and
;; can't be stopped). An HTTP error says so. A library whose download failed
;; isn't tried again for `+my/webkit-download-retry' seconds (each new view
;; would wait as long again), but when its install command is run.
(defvar +my/webkit--failed nil
  "(NAME TIME MESSAGE): the libraries whose download failed lately.")

(defun +my/webkit-installed-p (files dir)
  "Non-nil if FILES, ((FILE URL SHA256)...), are all in DIR."
  (seq-every-p (lambda (file) (file-exists-p (expand-file-name (car file) dir)))
               files))

(defun +my/webkit--received (buffer)
  "How much has come into BUFFER, a download's, so far (a redirect's too)."
  (let ((redirect (and (buffer-live-p buffer) (boundp 'url-redirect-buffer)
                       (buffer-local-value 'url-redirect-buffer buffer))))
    (+ (if (buffer-live-p buffer) (buffer-size buffer) 0)
       (if (and (buffer-live-p redirect) (not (eq redirect buffer))) (buffer-size redirect) 0))))

(defun +my/webkit--fetch (url file)
  "Download URL into FILE (see DOWNLOADS); an error if it can't."
  (require 'url)
  (require 'url-http)
  (require 'mm-decode)
  (let* ((done nil)
         (buffer (let ((url-asynchronous t))
                   (url-retrieve url (lambda (status) (setq done (cons (current-buffer) status)))
                                 nil t t)))
         (received -1)
         (since (float-time)))
    (unwind-protect
        (progn
          (condition-case nil
              (let ((inhibit-quit nil))
                (while (not done)
                  (let ((now (+my/webkit--received buffer)))
                    (unless (= now received)
                      (setq received now since (float-time))))
                  (when (> (- (float-time) since) +my/webkit-download-timeout)
                    (error "no answer from %s in %s s" (url-host (url-generic-parse-url url))
                           +my/webkit-download-timeout))
                  (accept-process-output nil 0.05)))
            (quit (error "download stopped (C-g)")))
          (pcase-let ((`(,data . ,status) done))
            (pcase (plist-get status :error)
              (`(error http ,code) (error "%s: HTTP %s" url code))
              (`(error ,why . ,more)
               (error "%s: %s (%s)" url why (string-trim (or (seq-find #'stringp more) "")))))
            (with-current-buffer data
              (unless (eql (bound-and-true-p url-http-response-status) 200)
                (error "%s: HTTP %s" url (bound-and-true-p url-http-response-status)))
              (let ((handle (mm-dissect-buffer t))
                    (mm-attachment-file-modes (default-file-modes)))
                (unwind-protect (mm-save-part-to-file handle file)
                  (mm-destroy-parts handle))))))
      ;; Its connection and buffers gone, however it ended.
      (dolist (gone (delete-dups (list buffer (car done))))
        (when (buffer-live-p gone)
          (when-let* ((process (get-buffer-process gone)))
            (delete-process process))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer gone)))))))

(defun +my/webkit--install-asked-p ()
  "Non-nil if the install under way was asked for: run by its command (M-x
+my/pdf-js-install, say), not for a page needing it."
  (let ((caller (nth 1 (backtrace-frame 1 #'+my/webkit-install))))
    (and caller this-command (eq caller this-command))))

(defun +my/webkit-install (name version files dir)
  "Download NAME's VERSION into DIR: FILES, ((FILE URL SHA256)...), FILE in
DIR (in folders of its own maybe) from URL, checked against its SHA-256.
Failed lately, not again yet (see DOWNLOADS)."
  (let ((failed (assoc name +my/webkit--failed)))
    (when (and failed (not (+my/webkit--install-asked-p))
               (< (- (float-time) (nth 1 failed)) +my/webkit-download-retry))
      (error "%s (%d min ago; tried again in %d min, or now by its install command)"
             (nth 2 failed) (/ (- (float-time) (nth 1 failed)) 60)
             (ceiling (- +my/webkit-download-retry (- (float-time) (nth 1 failed))) 60))))
  (setq +my/webkit--failed (assoc-delete-all name +my/webkit--failed))
  (condition-case err
      (pcase-dolist (`(,path ,url ,sha256) files)
        (let* ((file (expand-file-name path dir))
               (part (concat file ".part")))
          (make-directory (file-name-directory file) t)
          (when (file-exists-p part) (delete-file part))
          (message "Downloading %s: %s..." name path)
          (+my/webkit--fetch url part)
          (unless (equal (with-temp-buffer
                           (set-buffer-multibyte nil)
                           (insert-file-contents-literally part)
                           (secure-hash 'sha256 (current-buffer)))
                         sha256)
            (delete-file part)
            (error "%s isn't the file expected (SHA-256 differs), not installed" url))
          (rename-file part file t)))
    (error
     (let ((message (format "%s: %s" name (error-message-string err))))
       (push (list name (float-time) message) +my/webkit--failed)
       (signal (car err) (if (eq (car err) 'error) (list message) (cdr err))))))
  (message "%s %s installed in %s" name version dir))
