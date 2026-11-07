;;; $DOOMDIR/config/pdf/watch.el -*- lexical-binding: t; -*-
;; The pages on screen: watched, loaded, stopped. Loaded from config/pdf.el.

;; WATCHING THE PAGES ON SCREEN
;; Every 0.1 s, for each window showing a PDF, from its view's title (no
;; JavaScript, see WATCHING in config/webkit.el): its page in the window's
;; mode line, the toolbar's requests, and the mouse pointer the page wants
;; (hand: buttons, headings, thumbnails, links; text: the PDF's text; arrow).
(defun +my/pdf--show-page (window state)
  "The page of STATE in WINDOW's mode line (doom-modeline's PDF line, through
`+my/pdf--page')."
  (let* ((page (plist-get state :page))
         (pages (plist-get state :pages))
         (shown (cons (current-buffer)
                      (and (natnump pages) (> pages 0) (natnump page)
                           (format "  P%d/%d " page pages)))))
    (unless (equal shown (window-parameter window '+my/pdf-page))
      (set-window-parameter window '+my/pdf-page shown)
      (force-mode-line-update))))

(defun +my/pdf--page ()
  "The page of the PDF the mode line being drawn is for: its window's (each
window's view has its own). The window is the selected one meanwhile."
  (let ((shown (window-parameter nil '+my/pdf-page)))
    (and (eq (car shown) (current-buffer)) (cdr shown))))

;; doom-modeline's PDF line shows `doom-modeline--pdf-pages' as is, which in a
;; PDF is (:eval (+my/pdf--page)): a form the mode line only runs from
;; a variable marked risky.
(put 'doom-modeline--pdf-pages 'risky-local-variable t)

(defun +my/pdf--answer (xwidget state)
  "Run the toolbar's request in STATE, XWIDGET's, once (see above)."
  (let* ((action (plist-get state :action))
         (n (or (plist-get action :n) 0)))
    (unless (eql n (xwidget-get xwidget 'answered))
      (xwidget-put xwidget 'answered n)
      (when (> n 0)
        (pcase (plist-get action :name)
          ("preview" (+my/pdf-open-in-preview))
          ("print" (+my/pdf-print)))))))

(defun +my/pdf--watch (window xwidget)
  "WINDOW shows XWIDGET's view of the PDF: its page, the toolbar's requests,
the pointer (see above)."
  (when-let* ((state (+my/pdf--state xwidget)))
    (+my/pdf--show-page window state)
    (+my/pdf--answer xwidget state)
    (+my/webkit-pointer window (pcase (plist-get state :cursor)
                                 ("hand" 'hand) ("text" 'text) (_ 'arrow)))))

(defun +my/pdf--write-page (data)
  "Write the page's index.html, reading the PDF from DATA (a data-N.js)."
  (require 'json)
  (let ((page (format-spec
               +my/pdf--page-template
               `((?b . ,(+my/pdf--color 'default :background "#282c34"))
                 (?c . ,(if (eq (frame-parameter nil 'background-mode) 'light) "light" "dark"))
                 (?v . ,(+my/pdf--css-variables))
                 (?o . ,(+my/pdf--options))
                 (?p . ,(+my/webkit-file-url (file-name-as-directory +my/pdf-js-dir)))
                 (?j . ,(+my/webkit-file-url
                         (expand-file-name "config/pdf/pdf.js" doom-user-dir)))
                 (?d . ,(json-encode data))))))
    (with-temp-file (expand-file-name "index.html" +my/pdf--dir)
      (insert page))))

(defun +my/pdf--page-url ()
  "Make this buffer's page, in a folder of its own; return its URL. Without
PDF.js, the PDF's own (WebKit's viewer)."
  (if (not (+my/pdf-js-ensure))
      (progn (setq +my/pdf--native t)
             (+my/webkit-file-url buffer-file-name))
    (setq +my/pdf--native nil
          +my/pdf--dir (make-temp-file "pdf-" t)
          +my/pdf--data 0)
    (+my/pdf--write-page (+my/pdf--write-data))
    (+my/webkit-file-url (expand-file-name "index.html" +my/pdf--dir))))

(defun +my/pdf--url (_window)
  "The page a new view of the PDF loads (see VIEWS in config/webkit.el): made
the first time; written anew after, to start as the view latest looked at is
(settings, place)."
  (cond ((not +my/pdf--home)
         (setq +my/pdf--home (+my/pdf--page-url)))
        ((not +my/pdf--native)
         (+my/pdf--write-page (format "data-%d.js" +my/pdf--data))))
  +my/pdf--home)

(defun +my/pdf--js (script &optional all)
  "Run pdfx.SCRIPT in the selected window's page (ALL: in each of the PDF's
views), not waiting for an answer (see config/pdf.el)."
  (cond ((not (+my/webkit-xwidget)))
        (+my/pdf--native
         (message "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again"))
        (t (+my/webkit-execute (concat "window.pdfx && pdfx." script) all))))

(defun +my/pdf--stop ()
  "Keep the PDF's place, delete its page's folder (another mode, the buffer
killed); its views close after (config/webkit.el)."
  (+my/pdf--remember)
  (when (and +my/pdf--dir (file-directory-p +my/pdf--dir))
    (delete-directory +my/pdf--dir t))
  (setq +my/pdf--dir nil))

;; Quitting Emacs kills no buffers: the open PDFs' places would be lost, and
;; the pages' folders (a copy of each PDF) would stay.
(add-hook 'kill-emacs-hook
          (defun +my/pdf--cleanup-h ()
            (dolist (buffer (buffer-list))
              (when (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)
                (with-current-buffer buffer
                  (ignore-errors (+my/pdf--remember))))
              (when-let* ((dir (buffer-local-value '+my/pdf--dir buffer)))
                (ignore-errors (delete-directory dir t))))))

(defun +my/pdf--revert (&rest _)
  "Show the PDF anew from its file, where it was (see config/pdf.el)."
  (set-visited-file-modtime)
  (when-let* ((xwidgets (+my/webkit-xwidgets)))
    (if (or +my/pdf--native (not +my/pdf--dir))
        (dolist (xwidget xwidgets)
          (xwidget-webkit-goto-uri xwidget +my/pdf--home))
      (let ((data (+my/pdf--write-data)))
        ;; Also for the page loaded anew (back from a link, a new view).
        (+my/pdf--write-page data)
        (setq +my/pdf--searching nil)
        (+my/pdf--js (format "reload(%s)" (json-encode data)) t)))))
