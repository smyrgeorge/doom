;;; $DOOMDIR/config/pdf/page.el -*- lexical-binding: t; -*-
;; PDF.js and a PDF's page. Loaded from config/pdf.el.

(defvar-local +my/pdf--dir nil
  "The page's folder: index.html and the PDF's data, as base64.")

(defvar-local +my/pdf--data 0
  "N of the PDF's latest data-N.js.")

(defvar-local +my/pdf--native nil
  "Non-nil if WebKit's own viewer shows the PDF (no PDF.js).")

(defvar-local +my/pdf--home nil
  "The page's URL (see `+my/pdf--url').")

(defconst +my/pdf--page-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<link rel=\"stylesheet\" href=\"%ppdf_viewer.css\">
<style>
:root{%v}
html,body{margin:0;height:100%%;overflow:hidden;background:%b;color-scheme:%c}
#viewerContainer{position:absolute;inset:0;overflow:auto}
.pdfViewer.removePageBorders .page{margin:10px auto;box-shadow:0 1px 6px rgba(0,0,0,.45)}
.badge{position:fixed;right:14px;z-index:10;padding:3px 9px;border-radius:6px;
  font:12px -apple-system,sans-serif;white-space:pre;background:var(--bar);
  color:var(--fg);border:1px solid var(--border);pointer-events:none;opacity:0;transition:opacity .2s}
.badge.on{opacity:1}
#find{top:10px}
#page{bottom:12px}
</style></head><body>
<div id=\"viewerContainer\"><div id=\"viewer\" class=\"pdfViewer\"></div></div>
<div id=\"find\" class=\"badge\"></div><div id=\"page\" class=\"badge\"></div>
<script src=\"%ppdf.min.js\"></script>
<script src=\"%ppdf.worker.min.js\"></script>
<script src=\"%ppdf_viewer.js\"></script>
<script>window.PDFX_OPTIONS = %o;</script>
<script src=\"%j\"></script>
<script>
if (window.pdfx) pdfx.open(%d);
else { var b = document.getElementById('find'); b.textContent = 'PDF.js did not load'; b.className = 'badge on'; }
</script>
</body></html>
"
  "A PDF's page (see pdf.js), for `format-spec': %b the
background, %c the colour scheme, %v the theme's colours (CSS variables), %o
the settings (JSON), %p PDF.js's folder, %j the script, %d the data file's
name (JSON).")

;; PDF.JS
(defun +my/pdf--js-files ()
  "PDF.js's files, as `+my/webkit-install' takes them."
  (mapcar (lambda (file)
            (list (file-name-nondirectory (car file))
                  (format "https://cdn.jsdelivr.net/npm/pdfjs-dist@%s/%s"
                          +my/pdf-js-version (car file))
                  (cdr file)))
          +my/pdf-js-files))

(defun +my/pdf-js-installed-p ()
  "Non-nil if PDF.js is in `+my/pdf-js-dir'."
  (+my/webkit-installed-p (+my/pdf--js-files) +my/pdf-js-dir))

(defun +my/pdf-js-install ()
  "Download PDF.js into `+my/pdf-js-dir', checking each file's SHA-256."
  (interactive)
  (+my/webkit-install "PDF.js" +my/pdf-js-version (+my/pdf--js-files) +my/pdf-js-dir))

(defun +my/pdf-js-ensure ()
  "Non-nil if PDF.js is there, downloaded now if need be (see config/pdf.el)."
  (or (+my/pdf-js-installed-p)
      (condition-case err
          (progn (+my/pdf-js-install) t)
        (error (message "PDFs in WebKit's own viewer: %s" (error-message-string err))
               nil))))

;; THE PAGE (see pdf.js)
(defun +my/pdf--write-data ()
  "Write the PDF, as base64, to the page's next data-N.js; return its name."
  (let* ((name (format "data-%d.js" (setq +my/pdf--data (1+ +my/pdf--data))))
         (old (expand-file-name (format "data-%d.js" (1- +my/pdf--data))
                                +my/pdf--dir))
         (pdf buffer-file-name)
         (coding-system-for-write 'no-conversion))
    (with-temp-file (expand-file-name name +my/pdf--dir)
      (set-buffer-multibyte nil)
      (insert-file-contents-literally pdf)
      (base64-encode-region (point-min) (point-max) t)
      (goto-char (point-min))
      (insert "window.PDFX_DATA=\"")
      (goto-char (point-max))
      (insert "\";\n"))
    ;; The page has read the one before.
    (when (file-exists-p old)
      (delete-file old))
    name))

(defun +my/pdf--color (face attribute fallback)
  "FACE's ATTRIBUTE colour as #rrggbb (CSS doesn't know Emacs's colour
names), FALLBACK without one."
  (require 'color)
  (let ((color (face-attribute face attribute nil t)))
    (or (and (stringp color) (color-defined-p color)
             (apply #'color-rgb-to-hex (append (color-name-to-rgb color) '(2))))
        fallback)))

(defun +my/pdf--css-variables ()
  "The theme's colours, for the toolbar and the sidebar (CSS variables)."
  (format "--bg:%s;--bar:%s;--fg:%s;--dim:%s;--hover:%s;--accent:%s;--border:%s"
          (+my/pdf--color 'default :background "#282c34")
          (+my/pdf--color 'mode-line :background "#1d2026")
          (+my/pdf--color 'default :foreground "#bbc2cf")
          (+my/pdf--color 'shadow :foreground "#5b6268")
          (+my/pdf--color 'region :background "#3f444a")
          (+my/pdf--color 'link :foreground "#51afef")
          (+my/pdf--color 'vertical-border :foreground "#191b20")))

;; THE THEME, CHANGED
;; A page takes the theme's colours when it's written (a new view writes it
;; anew); the views open when the theme changes (SPC h t, its previews too)
;; take the new ones at once.
(defun +my/pdf--theme-script ()
  "JavaScript giving a page the theme's colours now (see above)."
  (let ((background (+my/pdf--color 'default :background "#282c34"))
        (scheme (if (eq (frame-parameter nil 'background-mode) 'light) "light" "dark")))
    (format "(function(){var h=document.documentElement,b=document.body;h.style.cssText=%S;b.style.background=%S;b.style.colorScheme=%S})()"
            (format "%s;background:%s;color-scheme:%s" (+my/pdf--css-variables) background scheme)
            background scheme)))

(defun +my/pdf-theme-h ()
  "The theme changed: each PDF's views in its colours (see above)."
  (dolist (buffer (buffer-list))
    (when (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)
      (with-current-buffer buffer
        (unless +my/pdf--native
          (+my/webkit-execute (+my/pdf--theme-script) t))))))

(add-hook 'doom-load-theme-hook #'+my/pdf-theme-h)

;; SETTINGS: the toolbar, the outline sidebar, dark pages (see config/pdf.el). The
;; page says them, and its page, in its title: "pdfx {json}".
(defun +my/pdf--state (&optional xwidget)
  "XWIDGET's page's settings and page (default: this buffer's view, see
`+my/webkit-xwidget'), a plist (:dark :toolbar :sidebar :view :outline
:page :pages :place :cursor :action), or nil before it has said them."
  (+my/webkit-title-json (or xwidget (+my/webkit-xwidget)) "pdfx "))

(defun +my/pdf--options ()
  "The settings a page starts with (JSON): this PDF's (a page written anew,
another window's view, see VIEWS), else the last PDF's looked at, else the
variables above; and its place, this PDF's or the one kept from last time (see
PLACES)."
  (require 'json)
  (let* ((own (+my/pdf--state))
         (last (or own
                   (seq-some (lambda (buffer)
                               (and (not (eq buffer (current-buffer)))
                                    (eq (buffer-local-value 'major-mode buffer)
                                        '+my/pdf-mode)
                                    (with-current-buffer buffer
                                      (+my/pdf--state))))
                             (buffer-list))))
         (get (lambda (key default) (if last (plist-get last key) default)))
         (bool (lambda (value) (if value "true" "false")))
         (place (or (plist-get own :place) (+my/pdf--kept-place))))
    (format "{\"dark\":%s,\"toolbar\":%s,\"sidebar\":%s,\"view\":%s,\"place\":%s,\"zoomStep\":%s,\"labels\":%s}"
            (funcall bool (funcall get :dark +my/pdf-dark-pages))
            (funcall bool (funcall get :toolbar +my/pdf-toolbar))
            (funcall bool (funcall get :sidebar +my/pdf-outline-sidebar))
            (json-encode (or (funcall get :view nil) "outline"))
            (if place (json-encode place) "null")
            +my/pdf-zoom-step
            (+my/pdf--labels))))

(defun +my/pdf--labels ()
  "The toolbar's words that differ between macOS and Linux (JSON): the
modifier of its keys' names (Cmd, Ctrl), the app SPC m p opens it in."
  (json-encode (list :mod (+my/os-key-name "Cmd" "Ctrl")
                     :viewer (+my/os-app-name 'viewer))))
