;;; $DOOMDIR/config/excalidraw/libraries.el -*- lexical-binding: t; -*-
;; Excalidraw's libraries. Loaded from config/excalidraw.el.

;; LIBRARIES (see config/excalidraw.el)
;; The library is the pages': each starts with its file's, and says in its
;; title when it changed (its version, see SAVING in sync.el); Emacs asks for it, keeps it
;; in the file and gives it to the other drawings' pages. libraries.excalidraw.com
;; ("Browse libraries") sends the library chosen to the drawing's address, a
;; file:// one Emacs never sees (in the browser, where a link out of the page
;; goes): the site opens in Emacs instead, and its way to that address (one of
;; no site) is stopped, the library taken from it. But its "Add to Excalidraw"
;; links open a new window, which a click (not a script's) didn't do in Emacs's
;; WebKit, and on its way to no site WebKit still says the site's address; so
;; the site is told to put the link clicked in its title instead, which Emacs
;; reads every 0.2 s while it's open (as WebKit pages' titles, see WATCHING in
;; config/webkit/js.el). A notice above it says what to do, and goes back to the
;; drawing.
(defconst +my/excalidraw--libraries "https://libraries.excalidraw.com"
  "Excalidraw's libraries' site.")

(defconst +my/excalidraw--library-return "https://excalidraw.emacs.invalid/"
  "Where libraries.excalidraw.com sends a library to add (see above): no
site has the name.")

(defun +my/excalidraw--library-text ()
  "The library's file's text, \"\" without one."
  (if (file-readable-p +my/excalidraw-library-file)
      (with-temp-buffer
        (insert-file-contents +my/excalidraw-library-file)
        (buffer-string))
    ""))

(defun +my/excalidraw--drawings ()
  "The buffers showing drawings."
  (seq-filter (lambda (buffer)
                (provided-mode-derived-p (buffer-local-value 'major-mode buffer)
                                         '+my/excalidraw-mode))
              (buffer-list)))

(defun +my/excalidraw--library-received (answer)
  "A page's library (see above): \"VERSION\\nTEXT\", TEXT an .excalidrawlib's."
  (pcase-let* ((xwidget +my/webkit-answering)
               (`(,version . ,text) (+my/excalidraw--versioned answer)))
    (when (and xwidget version
               (> version (or (xwidget-get xwidget 'library) 0)))
      (xwidget-put xwidget 'library version)
      (unless (or (string-empty-p text) (equal text (+my/excalidraw--library-text)))
        (make-directory (file-name-directory +my/excalidraw-library-file) t)
        (let ((coding-system-for-write 'utf-8-unix))
          (with-temp-file +my/excalidraw-library-file
            (insert text)))
        ;; The other pages, the other drawings'.
        (let ((script (format "window.exd && exd.setLibrary(\"%s\")" (+my/excalidraw--base64 text))))
          (dolist (buffer (+my/excalidraw--drawings))
            (with-current-buffer buffer
              (dolist (other (+my/webkit-xwidgets))
                (unless (eq other xwidget)
                  (+my/webkit-execute script other))))))))))

(defun +my/excalidraw--library-in (link)
  "The library LINK says to add (libraries.excalidraw.com's addLibrary=), or nil."
  (require 'url-util)
  (when (and (stringp link)
             (string-match "[#?&]addLibrary=\\([^&#]+\\)" link))
    (url-unhex-string (match-string 1 link))))

(defun +my/excalidraw--fetch (source)
  "The text of SOURCE: a URL (http(s), file://) or a file."
  (cond ((string-match-p "\\`https?://" source)
         (require 'url)
         (message "Downloading %s..." source)
         (let ((buffer (or (url-retrieve-synchronously source t nil 30)
                           (user-error "Couldn't download %s" source))))
           (unwind-protect
               (with-current-buffer buffer
                 (goto-char (point-min))
                 (unless (looking-at "HTTP/[0-9.]+ 200")
                   (user-error "Couldn't download %s: %s" source
                               (buffer-substring (point) (line-end-position))))
                 (re-search-forward "\r?\n\r?\n" nil 'move)
                 (decode-coding-string (buffer-substring-no-properties (point) (point-max)) 'utf-8))
             (kill-buffer buffer))))
        (t
         (let ((file (if (string-prefix-p "file:" source) (+my/webkit-url-file source)
                       (expand-file-name source))))
           (unless (file-readable-p file)
             (user-error "No such library: %s" source))
           (with-temp-buffer
             (insert-file-contents file)
             (buffer-string))))))

(defun +my/excalidraw--library-p (text)
  "Non-nil if TEXT is an .excalidrawlib's (version 2's libraryItems, 1's
library)."
  (let ((json (ignore-errors (json-parse-string text :object-type 'alist))))
    (and (consp json)
         (or (assq 'libraryItems json) (assq 'library json)))))

(defun +my/excalidraw--a-view ()
  "A drawing's view to add a library in: the selected window's, else one on
screen, else any."
  (or (and (derived-mode-p '+my/excalidraw-mode) (+my/webkit-xwidget))
      (seq-some (lambda (window)
                  (with-current-buffer (window-buffer window)
                    (and (derived-mode-p '+my/excalidraw-mode) (+my/webkit-xwidget window))))
                (window-list-1 nil 'nomini 'visible))
      (seq-some (lambda (buffer) (with-current-buffer buffer (+my/webkit-xwidget)))
                (+my/excalidraw--drawings))))

(defun +my/excalidraw--library-guess ()
  "A library the kill ring's latest names, for `+my/excalidraw-add-library'."
  (let ((latest (ignore-errors (current-kill 0 t))))
    (and (stringp latest)
         (string-match-p "addLibrary=\\|\\.excalidrawlib\\'" latest)
         (string-trim latest))))

(defun +my/excalidraw-add-library (source)
  "Add the library SOURCE to the drawings' (see above): an .excalidrawlib's
URL or file, or a link with addLibrary= in it. Merged in an open drawing's
page, its library panel opened."
  (interactive
   (list (read-string "Library (URL, file, or a link with addLibrary=): "
                      (+my/excalidraw--library-guess))))
  (let* ((xwidget (or (+my/excalidraw--a-view)
                      (user-error "Open a drawing first: the library is added in its page")))
         (source (string-trim source))
         (text (+my/excalidraw--fetch (or (+my/excalidraw--library-in source) source))))
    (unless (+my/excalidraw--library-p text)
      (user-error "Not an Excalidraw library: %s" source))
    (with-current-buffer (xwidget-buffer xwidget)
      (+my/webkit-execute (format "window.exd && exd.addLibrary(\"%s\")" (+my/excalidraw--base64 text))
                          xwidget))
    (message "Library added: in the drawing's library panel")))

(defconst +my/excalidraw--libraries-script
  "window.exdLibraries || (window.exdLibraries = document.addEventListener('click', (event) => {
  const link = event.target.closest && event.target.closest('a[href*=\"addLibrary=\"]');
  if (link) { event.preventDefault(); event.stopPropagation(); document.title = 'exd-library ' + link.href; }
}, true) || true);"
  "Run in the libraries' site: its \"Add to Excalidraw\" link clicked said in its
title (see above).")

(defun +my/excalidraw--libraries-url ()
  "libraries.excalidraw.com's address, as Excalidraw's Browse libraries has it."
  (require 'url-util)
  (format "%s/?target=_excalidraw&referrer=%s&useHash=true&token=emacs&theme=%s&version=2"
          +my/excalidraw--libraries (url-hexify-string +my/excalidraw--library-return)
          (if (+my/excalidraw--dark-p) "dark" "light")))

(defun +my/excalidraw--link-out (url)
  "A link out of a drawing's page: libraries.excalidraw.com in Emacs (see
above), the rest in the browser."
  (if (string-prefix-p +my/excalidraw--libraries url)
      (run-at-time 0 nil #'+my/excalidraw-browse-libraries url (current-buffer))
    (browse-url url)))

(defun +my/excalidraw-browse-libraries (&optional url drawing)
  "SPC m l: Excalidraw's libraries, libraries.excalidraw.com (URL), in
Emacs, in DRAWING's window (default: the current buffer's): its \"Add to
Excalidraw\" adds one to the drawings' library (see above)."
  (interactive)
  (let ((drawing (or drawing (current-buffer))))
    (unless (and (buffer-live-p drawing)
                 (provided-mode-derived-p (buffer-local-value 'major-mode drawing) '+my/excalidraw-mode))
      (user-error "Not in a drawing"))
    (require 'xwidget)
    (let ((window (or (get-buffer-window drawing) (selected-window))))
      (select-window window)
      (xwidget-webkit-new-session (or url (+my/excalidraw--libraries-url)))
      (let ((xwidget (xwidget-webkit-current-session)))
        (set-xwidget-query-on-exit-flag xwidget nil)
        (xwidget-put xwidget 'callback #'+my/excalidraw--libraries-callback)
        (xwidget-put xwidget '+my/excalidraw-drawing drawing)
        (xwidget-put xwidget '+my/excalidraw-window window)
        (xwidget-put xwidget '+my/excalidraw-watch
                     (run-with-timer 0.2 0.2 #'+my/excalidraw--libraries-watch xwidget))
        (when (fboundp '+my/banner-show)
          (+my/banner-show 'excalidraw-libraries
                           "Pick a library: its \"Add to Excalidraw\" adds it to your drawings' library"
                           :actions '(("Back to the drawing" . +my/excalidraw-libraries-back))))
        xwidget))))

(defun +my/excalidraw--libraries-watch (xwidget)
  "Every 0.2 s while XWIDGET's libraries' site is open: the library its title
says was chosen (see above); done once it's closed."
  (let ((title (and (buffer-live-p (xwidget-buffer xwidget))
                    (not (xwidget-get xwidget '+my/excalidraw-added))
                    (ignore-errors (xwidget-webkit-title xwidget)))))
    (cond ((not (stringp title))
           (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
             (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch))))
          ((string-prefix-p "exd-library " title)
           (+my/excalidraw--library-picked xwidget (+my/excalidraw--library-in title))))))

(defun +my/excalidraw--library-picked (xwidget library)
  "LIBRARY was chosen in XWIDGET's libraries' site: added after this event
(once), back in the drawing."
  (when (and library (not (xwidget-get xwidget '+my/excalidraw-added)))
    (xwidget-put xwidget '+my/excalidraw-added t)
    (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
      (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch)))
    (run-at-time 0 nil #'+my/excalidraw--library-chosen xwidget library)))

(defun +my/excalidraw-libraries-back ()
  "Close the libraries' site (the current buffer's), back to its drawing."
  (interactive)
  (when-let* ((xwidget (xwidget-webkit-current-session)))
    (+my/excalidraw--leave-libraries xwidget)))

(defun +my/excalidraw--leave-libraries (xwidget)
  "Close XWIDGET's libraries' site, its drawing shown again in its window;
return the drawing's buffer, if it's still there."
  (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
    (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch)))
  (let ((drawing (xwidget-get xwidget '+my/excalidraw-drawing))
        (window (xwidget-get xwidget '+my/excalidraw-window))
        (site (xwidget-buffer xwidget)))
    (when (and (buffer-live-p drawing) (window-live-p window))
      (set-window-buffer window drawing)
      (select-window window))
    (when (buffer-live-p site)
      (let ((kill-buffer-query-functions nil))
        (kill-buffer site)))
    (and (buffer-live-p drawing) drawing)))

(defun +my/excalidraw--libraries-callback (xwidget event-type)
  "WebKit's events in the libraries' site: on its way to a library to add,
stopped, the library added (once); others as usual."
  (let ((library (and (eq event-type 'load-changed)
                      (+my/excalidraw--library-in (xwidget-webkit-uri xwidget)))))
    (when (and (not library) (eq event-type 'load-changed)
               (equal (nth 3 last-input-event) "load-finished"))
      (xwidget-webkit-execute-script xwidget +my/excalidraw--libraries-script))
    (if (not library)
        (xwidget-webkit-callback xwidget event-type)
      (ignore-errors (xwidget-webkit-stop-loading xwidget))
      (+my/excalidraw--library-picked xwidget library))))

(defun +my/excalidraw--library-chosen (xwidget library)
  "LIBRARY was chosen in XWIDGET's libraries' site: back to the drawing, the
site closed, the library added."
  (if-let* ((drawing (+my/excalidraw--leave-libraries xwidget)))
      (with-current-buffer drawing
        (+my/excalidraw-add-library library))
    (+my/excalidraw-add-library library)))
