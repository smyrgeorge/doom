;;; $DOOMDIR/config/emacs/os.el -*- lexical-binding: t; -*-
;; What differs between macOS and Linux: the keys, and the other apps and
;; programs files go to (config/emacs.el, MACOS AND LINUX, says which).
;; Loaded from config/emacs.el, first: the other files use it.

(defun +my/macos-p ()
  "Non-nil on macOS (else Linux, or another Unix)."
  (eq system-type 'darwin))

;; KEYS (config/emacs.el)
(defun +my/os-key-name (mac linux)
  "A key's name, for messages and buttons: MAC (\"Cmd+C\") on macOS, else
LINUX (\"Ctrl+Shift+C\")."
  (if (+my/macos-p) mac linux))

;; OTHER APPS
(defun +my/os-app-name (what)
  "The app WHAT (`viewer': the one a file opens in, `files': the file
manager) is called here, for menus and buttons."
  (pcase what
    ('viewer (if (+my/macos-p) "Preview" "the default app"))
    ('files (if (+my/macos-p) "Finder" "the file manager"))))

(defun +my/os--run (program &rest args)
  "Start PROGRAM with ARGS, not waiting for it; on Linux a user error if it
isn't installed (macOS's open always is). Its failing (an exit status not
0) said once it ends, with what it wrote."
  (unless (or (+my/macos-p) (executable-find program))
    (user-error "%s isn't installed" program))
  (let ((output (generate-new-buffer " *os-run*" t)))
    (make-process
     :name program :buffer output :noquery t :connection-type 'pipe
     :command (cons program args)
     :sentinel (lambda (process _event)
                 (unless (process-live-p process)
                   (let ((said (with-current-buffer output (string-trim (buffer-string)))))
                     (kill-buffer output)
                     (unless (eql (process-exit-status process) 0)
                       (message "%s failed: %s" program
                                (if (string-empty-p said)
                                    (format "exit status %s" (process-exit-status process))
                                  said)))))))))

(defun +my/os--local (file verb what)
  "A user error if FILE is on another machine (remote, TRAMP): WHAT, an app
here (`+my/os-app-name'), can't VERB (\"open\") it."
  (when (file-remote-p file)
    (user-error "Can't %s a file on another machine in %s: %s" verb (+my/os-app-name what) file)))

(defun +my/os-open (file)
  "Open FILE in another app: Preview on macOS, its default app on Linux."
  (+my/os--local file "open" 'viewer)
  (if (+my/macos-p)
      (+my/os--run "open" "-a" "Preview" file)
    (+my/os--run "xdg-open" file)))

(defun +my/os-reveal (file)
  "Show FILE (or a folder) in the file manager, selected: Finder on macOS; on
Linux the file manager D-Bus has (Nautilus, Dolphin...), else its folder,
opened."
  (+my/os--local file "show" 'files)
  (cond ((+my/macos-p) (+my/os--run "open" "-R" file))
        ((+my/os--reveal-dbus file))
        (t (+my/os--run "xdg-open" (file-name-directory (directory-file-name file))))))

(defun +my/os--reveal-dbus (file)
  "Ask the file manager to show FILE selected (org.freedesktop.FileManager1,
on D-Bus): non-nil if one could be asked."
  (when (and (featurep 'dbusbind) (require 'dbus nil t))
    (ignore-errors
      (when (dbus-ping :session "org.freedesktop.FileManager1" 1000)
        (dbus-call-method-asynchronously
         :session "org.freedesktop.FileManager1" "/org/freedesktop/FileManager1"
         "org.freedesktop.FileManager1" "ShowItems" nil
         (list :array (browse-url-file-url (expand-file-name file))) "")
        t))))

(defun +my/os-print (file)
  "Print FILE: in Preview's print dialog on macOS (it asks once to let Emacs
control Preview); on Linux on the default printer (lp), after asking."
  (if (+my/macos-p)
      (make-process
       :name "os-print"
       :noquery t
       :command (list "osascript"
                      "-e" "on run argv"
                      "-e" "tell application \"Preview\""
                      "-e" "activate"
                      "-e" "print ((POSIX file (item 1 of argv)) as alias) with print dialog"
                      "-e" "end tell"
                      "-e" "end run"
                      file)
       :sentinel (lambda (process _event)
                   (when (and (eq (process-status process) 'exit)
                              (/= (process-exit-status process) 0))
                     (message "Couldn't print through Preview: SPC m p opens it there, then Cmd+P"))))
    (unless (executable-find "lp")
      (user-error "Printing needs lp (CUPS): or SPC m p opens it in the default app"))
    (when (y-or-n-p (format "Print %s on the default printer? " (file-name-nondirectory file)))
      (with-temp-buffer
        (if (zerop (call-process "lp" nil t nil "--" file))
            (message "Sent to the printer: %s" (string-trim (buffer-string)))
          (user-error "Couldn't print: %s" (string-trim (buffer-string))))))))

;; THE CLIPBOARD'S IMAGES
(defun +my/os-copy-image (file type)
  "FILE's bytes on the clipboard as an image of TYPE (`png' or `jpeg'), to
paste in other apps."
  (with-temp-buffer
    (let ((status
           (cond
            ((+my/macos-p)
             (call-process "osascript" nil t nil
                           "-e" "on run argv"
                           "-e" (format "set the clipboard to (read (POSIX file (item 1 of argv)) as «class %s»)"
                                        (if (eq type 'jpeg) "JPEG" "PNGf"))
                           "-e" "end run"
                           file))
            ((and (getenv "WAYLAND_DISPLAY") (executable-find "wl-copy"))
             (call-process "wl-copy" file t nil "--type" (format "image/%s" type)))
            ((executable-find "xclip")
             (call-process "xclip" file t nil
                           "-selection" "clipboard" "-t" (format "image/%s" type)))
            (t (user-error "Copying an image needs %s"
                           (if (getenv "WAYLAND_DISPLAY") "wl-copy (wl-clipboard)" "xclip"))))))
      (unless (eql status 0)
        (user-error "Couldn't copy the image: %s" (string-trim (buffer-string)))))))

;; IMAGE EDITING
(defun +my/os-imagemagick ()
  "ImageMagick's command: magick (7), else convert (6, Debian's and
Ubuntu's); nil if it's not installed."
  (or (executable-find "magick") (executable-find "convert")))

(defconst +my/os--image-transforms
  '((rotate-right "-r" "90" "-rotate" "90")
    (rotate-left "-r" "270" "-rotate" "270")
    (flip-horizontal "-f" "horizontal" "-flop")
    (flip-vertical "-f" "vertical" "-flip"))
  "(TRANSFORM SIPS-ARG SIPS-VALUE IMAGEMAGICK-ARGS...).")

(defun +my/os-image-transform (file transform)
  "Change image FILE in place by TRANSFORM (`rotate-right', `rotate-left',
`flip-horizontal', `flip-vertical'): with sips on macOS, ImageMagick on
Linux. A user error if it couldn't."
  (let* ((spec (or (alist-get transform +my/os--image-transforms)
                   (error "No image transform %s" transform)))
         (magick (and (not (+my/macos-p)) (+my/os-imagemagick))))
    (unless (or (+my/macos-p) magick)
      (user-error "Rotating and flipping need ImageMagick (magick or convert)"))
    (with-temp-buffer
      (unless (zerop (if (+my/macos-p)
                         (call-process "sips" nil t nil (nth 0 spec) (nth 1 spec) file)
                       (apply #'call-process magick nil t nil
                              (append (list file) (nthcdr 2 spec) (list file)))))
        (user-error "Couldn't change the image: %s" (string-trim (buffer-string)))))))

(defun +my/os-image-to-png (from to)
  "Make PNG TO from image FROM: with sips (macOS), or ImageMagick (also for
what sips can't read: SVG). Non-nil if TO was made."
  (or (and (+my/macos-p)
           (eql 0 (ignore-errors (call-process "sips" nil nil nil "-s" "format" "png" from "--out" to)))
           (file-exists-p to))
      (when-let* ((magick (+my/os-imagemagick)))
        (and (zerop (call-process magick nil nil nil from (concat "png:" to)))
             (file-exists-p to)))))

;; DESKTOP NOTIFICATIONS (config/emacs.el)
(defun +my/os--applescript-string (text)
  "TEXT as an AppleScript string, on one line."
  (format "\"%s\"" (replace-regexp-in-string
                    "[\"\\]" "\\\\\\&"
                    (replace-regexp-in-string "[\n\r]+" " " text))))

(defun +my/os--notify-macos (title body)
  "TITLE and BODY in macOS's Notification Center (config/emacs.el): through
Emacs's own AppleScript while it has a GUI display (posted as Emacs's);
else (a terminal's Emacs, a daemon with only terminal frames: its
AppleScript errors there) through osascript, posted as Script Editor's."
  (let ((script (format "display notification %s with title %s"
                        (+my/os--applescript-string body)
                        (+my/os--applescript-string title))))
    (if (and (fboundp 'do-applescript)
             (fboundp 'x-display-list)
             (x-display-list))
        (do-applescript script)
      (+my/os--run "osascript" "-e" script))
    t))

(defun +my/os--dbus-notifications-p ()
  "Non-nil if the desktop's notifications answer on D-Bus."
  (and (featurep 'dbusbind)
       (require 'notifications nil t)
       (ignore-errors (dbus-ping :session notifications-service 500))))

(defun +my/os--notify-linux (title body on-click)
  "TITLE and BODY in the desktop's notifications (config/emacs.el); ON-CLICK, a
function, run on a click (D-Bus only). Nil if neither D-Bus nor notify-send
can show it."
  (cond ((+my/os--dbus-notifications-p)
         (apply #'notifications-notify
                :title title :body body :app-name "Emacs" :app-icon "emacs"
                (and on-click
                     (list :actions '("default" "Show")
                           :on-action (lambda (_id _action) (funcall on-click)))))
         t)
        ((executable-find "notify-send")
         ;; "--": a title or body starting with "-" isn't an option.
         (+my/os--run "notify-send" "--app-name=Emacs" "--icon=emacs" "--" title body)
         t)))

(defun +my/os-notify (title body &optional on-click)
  "Show a desktop notification, TITLE and BODY (config/emacs.el, DESKTOP
NOTIFICATIONS). ON-CLICK, a function, runs when it's clicked (Linux; on
macOS a click brings Emacs forward). Non-nil if it was shown."
  (if (+my/macos-p)
      (+my/os--notify-macos title body)
    (+my/os--notify-linux title body on-click)))
