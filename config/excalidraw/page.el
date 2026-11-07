;;; $DOOMDIR/config/excalidraw/page.el -*- lexical-binding: t; -*-
;; Excalidraw and a drawing's page. Loaded from config/excalidraw.el.

;; EXCALIDRAW

(defvar-local +my/excalidraw--dir nil
  "The page's folder (index.html).")

(defconst +my/excalidraw--page-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<style>html,body,#app{margin:0;height:100%%;overflow:hidden;background:%b}</style>
<script>window.EXCALIDRAW_ASSET_PATH = %a;</script>
<script src=\"%preact.production.min.js\"></script>
<script src=\"%preact-dom.production.min.js\"></script>
<script src=\"%pexcalidraw.production.min.js\"></script>
<script>window.EXD_OPTIONS = %o;</script>
<script src=\"%j\"></script>
</head><body><div id=\"app\"></div>
<script>
if (window.exd) exd.open(%d, %l);
else document.title = 'exd ' + JSON.stringify({error: 'Excalidraw did not load'});
</script>
</body></html>
"
  "A drawing's page (see excalidraw.js), for `format-spec': %b the
background, %a Excalidraw's folder (JSON), %p its URL, %o the settings (JSON),
%j the script, %d the drawing (the file's text as base64, JSON), %l the
library (its file's text so, see libraries.el).")

(defun +my/excalidraw--files ()
  "Excalidraw's files, as `+my/webkit-install' takes them."
  (mapcar (lambda (file)
            (list (nth 0 file) (concat "https://cdn.jsdelivr.net/npm/" (nth 1 file)) (nth 2 file)))
          +my/excalidraw-files))

(defun +my/excalidraw-installed-p ()
  "Non-nil if Excalidraw is in `+my/excalidraw-dir'."
  (+my/webkit-installed-p (+my/excalidraw--files) +my/excalidraw-dir))

(defun +my/excalidraw-install ()
  "Download Excalidraw into `+my/excalidraw-dir', checking each file's SHA-256."
  (interactive)
  (+my/webkit-install "Excalidraw" +my/excalidraw-version (+my/excalidraw--files)
                      +my/excalidraw-dir))

(defun +my/excalidraw-ensure ()
  "Non-nil if Excalidraw is there, downloaded now if need be (see config/excalidraw.el)."
  (or (+my/excalidraw-installed-p)
      (condition-case err
          (progn (+my/excalidraw-install) t)
        (error (message "Drawings open as their files (no Excalidraw): %s"
                        (error-message-string err))
               nil))))

;; THE PAGE (see excalidraw.js)
(defun +my/excalidraw--dark-p ()
  "Non-nil if drawings show on a dark canvas (see `+my/excalidraw-theme')."
  (pcase +my/excalidraw-theme
    ('dark t)
    ('light nil)
    (_ (eq (frame-parameter nil 'background-mode) 'dark))))

(defun +my/excalidraw--background ()
  "The canvas's colour, for the cover while a view loads (config/webkit.el)."
  (if (+my/excalidraw--dark-p) "#121212" "#ffffff"))

(defun +my/excalidraw--json (object)
  "OBJECT as JSON, a string of characters (`json-serialize' gives UTF-8
bytes, which a script made with them would carry as raw bytes)."
  (decode-coding-string (json-serialize object) 'utf-8 t))

(defun +my/excalidraw--base64 (text)
  "TEXT, UTF-8, as base64 on one line."
  (base64-encode-string (encode-coding-string text 'utf-8 t) t))

(defun +my/excalidraw--options ()
  "The settings a page starts with (JSON): the drawing's kind, the canvas,
how long after a change it's exported, and the CDN folder its SVG's fonts are
named in (Excalidraw adds /dist/excalidraw-assets/)."
  (+my/excalidraw--json (list :kind (if (+my/excalidraw--json-p) "json" "svg")
                        :dark (if (+my/excalidraw--dark-p) t :false)
                        :exportDelay +my/excalidraw-export-delay
                        :fonts (concat "https://cdn.jsdelivr.net/npm/@excalidraw/excalidraw@"
                                       +my/excalidraw-version)
                        :libraryReturn +my/excalidraw--library-return)))

(defun +my/excalidraw--page ()
  "The drawing's page, with the drawing as the buffer has it."
  (let ((assets (+my/webkit-file-url (file-name-as-directory +my/excalidraw-dir))))
    (format-spec
     +my/excalidraw--page-template
     `((?b . ,(+my/excalidraw--background))
       (?a . ,(+my/excalidraw--json assets))
       (?p . ,assets)
       (?o . ,(+my/excalidraw--options))
       (?j . ,(+my/webkit-file-url (expand-file-name "config/excalidraw/excalidraw.js" doom-user-dir)))
       (?d . ,(+my/excalidraw--json (+my/excalidraw--base64
                               (buffer-substring-no-properties (point-min) (point-max)))))
       (?l . ,(+my/excalidraw--json (+my/excalidraw--base64 (+my/excalidraw--library-text))))))))

(defun +my/excalidraw--write-page ()
  "Write the page's index.html (its folder made the first time); return it.
Written anew as the drawing changes: a view loading it shows it as it is."
  (unless (and +my/excalidraw--dir (file-directory-p +my/excalidraw--dir))
    (setq +my/excalidraw--dir (make-temp-file "excalidraw-" t)))
  (let ((file (expand-file-name "index.html" +my/excalidraw--dir))
        (page (+my/excalidraw--page))
        (coding-system-for-write 'utf-8-unix))
    (with-temp-file file
      (insert page))
    file))

(defun +my/excalidraw--url (_window)
  "The page a new view of the drawing loads (see VIEWS in config/webkit.el)."
  (+my/webkit-file-url (+my/excalidraw--write-page)))

(defun +my/excalidraw--loaded (xwidget)
  "XWIDGET's page has (re)loaded: its drawing starts at version 0 (see
SAVING)."
  (xwidget-put xwidget 'seen 0)
  (xwidget-put xwidget 'fetched 0)
  (xwidget-put xwidget 'library 0))

(defun +my/excalidraw--stop ()
  "Delete the page's folder (another mode, the buffer killed); its views
close after (config/webkit.el)."
  (when (and +my/excalidraw--dir (file-directory-p +my/excalidraw--dir))
    (delete-directory +my/excalidraw--dir t))
  (setq +my/excalidraw--dir nil)
  (+my/excalidraw--show-error nil))

;; Quitting Emacs kills no buffers: the pages' folders would stay.
(add-hook 'kill-emacs-hook
          (defun +my/excalidraw--cleanup-h ()
            (dolist (buffer (buffer-list))
              (when-let* ((dir (buffer-local-value '+my/excalidraw--dir buffer)))
                (ignore-errors (delete-directory dir t))))))

(defun +my/excalidraw-toggle-dark ()
  "SPC m d: drawings on a dark canvas, or a light one (see config/excalidraw.el)."
  (interactive)
  (let ((dark (not (+my/excalidraw--dark-p))))
    (setq +my/excalidraw-theme (if dark 'dark 'light))
    (dolist (buffer (buffer-list))
      (when (provided-mode-derived-p (buffer-local-value 'major-mode buffer) '+my/excalidraw-mode)
        (with-current-buffer buffer
          (+my/webkit-execute (format "window.exd && exd.set({dark: %s})" (if dark "true" "false"))
                              t))))
    (message "Dark canvas %s" (if dark "on" "off"))))
