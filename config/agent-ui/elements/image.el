;;; $DOOMDIR/config/agent-ui/elements/image.el -*- lexical-binding: t; -*-
;; Agent UI's image: a picture file (an Excalidraw drawing's .excalidraw.svg
;; too) shown in a graphic Emacs. Loaded from config/agent-ui/elements.el.
;;
;; At most the pane's width (WIDTH: a share of it) and HEIGHT lines, never
;; above its own size; in a terminal, a line naming it. RET or a click opens
;; it (`agent-ui-open-file-function': the image viewer, Excalidraw for a
;; drawing). A file that isn't there is said, not an error.
;;
;; From a URL: downloaded once in the background (curl) into
;; `agent-ui-image-cache-directory', named by its hash, its extension its
;; type's; then shown as a file. Meanwhile, and if it fails, said in its place.

(require 'subr-x)

(defcustom agent-ui-open-file-function #'find-file-other-window
  "Opens a file an element shows (an image), given its name."
  :type 'function :group 'agent-ui)

(defcustom agent-ui-image-cache-directory (locate-user-emacs-file "agent-ui/images/")
  "Where images from URLs are kept once downloaded (config/agent-ui.el:
under Doom's cache)."
  :type 'directory :group 'agent-ui)

(defvar agent-ui-image-fetch-function #'agent-ui-image-curl
  "Downloads a URL into a file, then calls back with nil, or an error
message: called with URL, FILE and the callback (tests replace it).")

(defvar agent-ui-image--fetches (make-hash-table :test #'equal)
  "URLs being downloaded (fetching), or that failed: (:error MESSAGE :time
TIME).")

;; ====== FROM A URL ======

(defun agent-ui-image-curl (url file callback)
  "Download URL into FILE with curl, in the background; then CALLBACK with
nil, or what went wrong."
  (if (not (executable-find "curl"))
      (funcall callback "curl isn't installed")
    (let ((output (generate-new-buffer " *agent-ui-image*")))
      (make-process
       :name "agent-ui-image" :buffer output :noquery t :connection-type 'pipe
       :command (list "curl" "--silent" "--show-error" "--fail" "--location" "--max-time" "60"
                      "--max-filesize" "52428800" "--output" file url)
       :sentinel (lambda (process _)
                   (unless (process-live-p process)
                     (let ((message (with-current-buffer output (string-trim (buffer-string))))
                           (status (process-exit-status process)))
                       (kill-buffer output)
                       (funcall callback
                                (cond ((= status 0) nil)
                                      ((string-empty-p message) (format "curl exited with %d" status))
                                      ;; curl's words, without its name and code.
                                      (t (replace-regexp-in-string
                                          "\\`\\(?:curl: \\)?([0-9]+) " "" message)))))))))))

(defun agent-ui-image--stem (url)
  (expand-file-name (sha1 url) agent-ui-image-cache-directory))

(defun agent-ui-image--cached (url)
  "URL's image, if it was downloaded: its file."
  (when (file-directory-p agent-ui-image-cache-directory)
    (car (directory-files agent-ui-image-cache-directory t
                          (concat "\\`" (sha1 url) "\\.[a-z]+\\'")))))

(defun agent-ui-image--fetched (url part error)
  "URL's download into PART ended, ERROR what went wrong (nil: none): kept
under its type's extension if it's an image; the canvases redrawn."
  (let* ((type (and (not error) (file-exists-p part) (image-type-from-file-header part)))
         (error (or error (unless type "not an image"))))
    (if error
        (progn (puthash url (list :error error :time (float-time)) agent-ui-image--fetches)
               (ignore-errors (delete-file part)))
      (rename-file part (concat (agent-ui-image--stem url) "."
                                (pcase type ('jpeg "jpg") ('xpm "xpm") (_ (symbol-name type))))
                   t)
      (remhash url agent-ui-image--fetches))
    (dolist (canvas (agent-ui-canvases))
      (agent-ui-canvas-redraw canvas))))

(defun agent-ui-image--fetch (url)
  "Start downloading URL, unless it is already."
  (unless (gethash url agent-ui-image--fetches)
    (puthash url 'fetching agent-ui-image--fetches)
    (make-directory agent-ui-image-cache-directory t)
    (let ((part (concat (agent-ui-image--stem url) ".part")))
      (condition-case err
          (funcall agent-ui-image-fetch-function url part
                   (lambda (error) (agent-ui-image--fetched url part error)))
        (error (agent-ui-image--fetched url part (error-message-string err)))))))

(defun agent-ui-image--source (props)
  "PROPS' image: (FILE . WHY), WHY why it isn't shown (nil: it is). From a
URL: its download, started if it isn't there."
  (let ((file (plist-get props :file))
        (url (plist-get props :url)))
    (cond
     (file (cons file (unless (file-readable-p file) "not found")))
     ((agent-ui-image--cached url) (cons (agent-ui-image--cached url) nil))
     (t
      (agent-ui-image--fetch url)
      (let ((state (gethash url agent-ui-image--fetches)))
        (cons nil (if (eq state 'fetching)
                      "downloading…"
                    (format "couldn't download it: %s" (plist-get state :error)))))))))

;; ====== DRAWING ======

(defun agent-ui-image--open (file url)
  "Open the image: FILE, else URL in the browser."
  (if file (funcall agent-ui-open-file-function file) (browse-url url)))

(defun agent-ui-image--line (props ctx &optional why)
  "The line naming PROPS' image (in a terminal; WHY it isn't shown), CTX's
width at most."
  (let* ((source (agent-ui-image--source props))
         (file (car source))
         (url (plist-get props :url))
         (alt (plist-get props :alt)))
    (agent-ui-truncate
     (concat (propertize "▣ " 'face 'agent-ui-accent)
             (agent-ui-button (if url url (abbreviate-file-name file))
                              (lambda () (agent-ui-image--open file url))
                              "RET: open the image")
             (if alt (concat "  " alt) "")
             (if why
                 (propertize (concat "  (" why ")")
                             'face (if (string-prefix-p "couldn't" why) 'agent-ui-error 'agent-ui-muted))
               ""))
     (plist-get ctx :width))))

(defun agent-ui-image--text (props ctx)
  (agent-ui-image--line props ctx (cdr (agent-ui-image--source props))))

(defun agent-ui-image--gui (props ctx)
  (let* ((source (agent-ui-image--source props))
         (file (car source)))
    (cond
     ((cdr source) (agent-ui-image--line props ctx (cdr source)))
     ((not (image-supported-file-p file)) (agent-ui-image--line props ctx "not an image Emacs shows"))
     (t
      (let* ((width (round (* (plist-get ctx :width) (plist-get ctx :char-width)
                              (/ (plist-get props :width) 100.0))))
             (height (* (plist-get props :height) (plist-get ctx :line-height)))
             (image (create-image file nil nil :max-width width :max-height height :ascent 'center)))
        (concat (agent-ui-button (propertize " " 'display image)
                                 (lambda () (funcall agent-ui-open-file-function file))
                                 (format "%s: RET opens it" (or (plist-get props :url) (abbreviate-file-name file))))
                (if-let* ((alt (plist-get props :alt)))
                    (concat "\n" (propertize alt 'face 'agent-ui-muted))
                  "")))))))

(agent-ui-define image
  "An image file (PNG, JPEG, GIF, WebP, SVG; an Excalidraw drawing's
.excalidraw.svg too), or one from a URL (downloaded once, kept), shown in
a graphic Emacs at most WIDTH percent of the pane wide and HEIGHT lines
high (never above its own size); in a terminal, a line naming it. RET
opens it. FILE: relative to your directory."
  :props ((file file "The image file (or give url)")
          (url string "The image's web address, http(s) (or give file)")
          (alt string "What it shows (said under it; a terminal's only text)")
          (width integer "At most this percentage of the pane's width" :default 100)
          (height integer "At most so many lines high" :default 20))
  :example (:title "The login page" :file "screenshots/login.png" :alt "After the fix" :width 60)
  :check (lambda (props)
           (let ((file (plist-get props :file)) (url (plist-get props :url)))
             (unless (xor file url)
               (agent-ui--fail "image: give file or url, one of them"))
             (when (and url (not (string-match-p "\\`https?://[^ \t\n]+\\'" url)))
               (agent-ui--fail "image: url is an http(s) address, not %s (a file of yours: file)"
                               (agent-ui--show-value url))))
           (unless (<= 1 (plist-get props :width) 100)
             (agent-ui--fail "image: width is a percentage, 1 to 100"))
           (unless (<= 1 (plist-get props :height) 200)
             (agent-ui--fail "image: height is lines, 1 to 200"))
           props)
  ;; Shown again: a download that failed tried again (not more than every 30s).
  :prepare (lambda (element)
             (let* ((url (plist-get element :url))
                    (state (and url (gethash url agent-ui-image--fetches))))
               (when (and (consp state) (> (- (float-time) (plist-get state :time)) 30))
                 (remhash url agent-ui-image--fetches)))
             element)
  :text #'agent-ui-image--text
  :gui #'agent-ui-image--gui)
