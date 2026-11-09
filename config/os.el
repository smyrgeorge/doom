;;; $DOOMDIR/config/os.el -*- lexical-binding: t; -*-
;; What differs between macOS and Linux: the keys, and the other apps and
;; programs files go to (another app, the file manager, the printer, the
;; clipboard's images, image editing). Loaded from config.el, first: the other
;; files use it.

;; ====== VARIABLES ======

;; KEYS
;; On macOS this config's keys use Cmd (Super, `s-'), as macOS's apps do.
;; Linux's desktops keep most Super keys for themselves (and a terminal can't
;; send Super at all), so on Linux each Cmd key also has a Ctrl key, as Linux's
;; apps have them (docs/keybindings.md lists both):
;; - Ctrl where Vim and Emacs leave it free: Ctrl+1..9 (tabs), Ctrl+= / Ctrl+-
;;   / Ctrl+0 (zoom), Ctrl+P (print), Ctrl+S (a drawing, a merge);
;; - Ctrl+Shift where Ctrl is Vim's (Ctrl+B, Ctrl+W, Ctrl+C, Ctrl+V...), as
;;   Linux's terminals copy with Ctrl+Shift+C;
;; - Alt+← / Alt+→ back / forward, as browsers.
;; The Cmd keys stay bound too (Super, where the desktop lets it through).
;; macOS gets none of the Linux keys: its keys are as they were.

;; OTHER APPS (see `+my/os-open', `+my/os-reveal', `+my/os-print')
;; macOS: Preview and Finder (open), Preview's print dialog (osascript).
;; Linux: the file's default app and the file manager (xdg-open, D-Bus), the
;; default printer (lp, after asking).

;; THE CLIPBOARD'S IMAGES (`+my/os-copy-image')
;; macOS: osascript. Linux: wl-copy (Wayland) or xclip (X11).

;; IMAGE EDITING (`+my/os-image-transform', `+my/os-image-to-png')
;; macOS: sips. Linux: ImageMagick (magick, or convert: ImageMagick 6).

;; DESKTOP NOTIFICATIONS (`+my/os-notify', config/notify.el's)
;; macOS: Notification Center, posted by Emacs itself (AppleScript's display
;; notification, `do-applescript'; osascript's without it); macOS asks once
;; whether Emacs may notify (System Settings > Notifications > Emacs). A click
;; brings Emacs forward.
;; Linux: the desktop's notifications, through D-Bus (`notifications-notify':
;; a click runs the caller's function), else notify-send.

;; ====== CODE ======

(defun +my/macos-p ()
  "Non-nil on macOS (else Linux, or another Unix)."
  (eq system-type 'darwin))

;; KEYS (see above)
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
isn't installed (macOS's open always is)."
  (unless (or (+my/macos-p) (executable-find program))
    (user-error "%s isn't installed" program))
  (apply #'call-process program nil 0 nil args))

(defun +my/os-open (file)
  "Open FILE in another app: Preview on macOS, its default app on Linux."
  (if (+my/macos-p)
      (+my/os--run "open" "-a" "Preview" file)
    (+my/os--run "xdg-open" file)))

(defun +my/os-reveal (file)
  "Show FILE (or a folder) in the file manager, selected: Finder on macOS; on
Linux the file manager D-Bus has (Nautilus, Dolphin...), else its folder,
opened."
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

;; DESKTOP NOTIFICATIONS (see above)
(defun +my/os--applescript-string (text)
  "TEXT as an AppleScript string, on one line."
  (format "\"%s\"" (replace-regexp-in-string
                    "[\"\\]" "\\\\\\&"
                    (replace-regexp-in-string "[\n\r]+" " " text))))

(defun +my/os--notify-macos (title body)
  "TITLE and BODY in macOS's Notification Center (see above)."
  (let ((script (format "display notification %s with title %s"
                        (+my/os--applescript-string body)
                        (+my/os--applescript-string title))))
    (if (fboundp 'do-applescript)
        (do-applescript script)
      (+my/os--run "osascript" "-e" script))
    t))

(defun +my/os--dbus-notifications-p ()
  "Non-nil if the desktop's notifications answer on D-Bus."
  (and (featurep 'dbusbind)
       (require 'notifications nil t)
       (ignore-errors (dbus-ping :session notifications-service 500))))

(defun +my/os--notify-linux (title body on-click)
  "TITLE and BODY in the desktop's notifications (see above); ON-CLICK, a
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
         (+my/os--run "notify-send" "--app-name=Emacs" "--icon=emacs" title body)
         t)))

(defun +my/os-notify (title body &optional on-click)
  "Show a desktop notification, TITLE and BODY (see DESKTOP NOTIFICATIONS
above). ON-CLICK, a function, runs when it's clicked (Linux; on macOS a click
brings Emacs forward). Non-nil if it was shown."
  (if (+my/macos-p)
      (+my/os--notify-macos title body)
    (+my/os--notify-linux title body on-click)))
