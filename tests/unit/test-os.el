;;; tests/unit/test-os.el -*- lexical-binding: t; -*-
;; config/emacs/os.el: what differs between macOS and Linux. Each function on
;; each system (`system-type' let-bound), the programs it would run recorded,
;; not run (tests/helper.el records the apps it starts, `+test-os-runs'); and
;; ImageMagick's rotating for real where it's installed.

;; ====== HELPERS ======

(defmacro +test-os--with-programs (programs &rest body)
  "BODY with only PROGRAMS (names) installed, as `executable-find' sees it."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'executable-find)
              (lambda (name &rest _) (and (member name ,programs) (concat "/usr/bin/" name)))))
     ,@body))

(defmacro +test-os--recording-calls (&rest body)
  "BODY with `call-process' recorded in `calls' ((PROGRAM INFILE ARGS...),
latest first), returning `status'."
  (declare (indent 0))
  `(let ((calls nil) (status 0))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program infile _destination _display &rest args)
                  (push (append (list program infile) args) calls)
                  status)))
       ,@body)))

(defun +test-os--png (name width height)
  "A WIDTH×HEIGHT PNG NAME in the test's folder, made by ImageMagick."
  (let ((file (+test-tmp-file (concat "os/" name))))
    (should (zerop (call-process (+my/os-imagemagick) nil nil nil
                                 "-size" (format "%dx%d" width height) "xc:red" file)))
    file))

(defun +test-os--size (file)
  "FILE's (WIDTH HEIGHT), as ImageMagick reads them."
  (with-temp-buffer
    (call-process (+my/os-imagemagick) nil t nil file "-format" "%w %h" "info:")
    (mapcar #'string-to-number (split-string (buffer-string)))))

;; ====== THE SYSTEM ======

(ert-deftest os/macos-p ()
  (+test-on-macos (should (+my/macos-p)))
  (+test-on-linux (should-not (+my/macos-p)))
  (let ((system-type 'berkeley-unix)) (should-not (+my/macos-p))))

;; ====== OTHER APPS ======

(ert-deftest os/open-in-another-app ()
  "macOS: Preview. Linux: the file's default app (xdg-open)."
  (let ((+test-os-runs nil))
    (+test-on-macos (+my/os-open "/a/b.pdf"))
    (+test-on-linux (+my/os-open "/a/b.pdf"))
    (should (equal +test-os-runs '(("xdg-open" "/a/b.pdf") ("open" "-a" "Preview" "/a/b.pdf"))))))

(ert-deftest os/reveal-in-the-file-manager ()
  "macOS: Finder, the file selected. Linux: the file manager D-Bus has, it
selected; without one, its folder opened."
  (let ((+test-os-runs nil))
    (+test-on-macos (+my/os-reveal "/a/b.pdf"))
    (should (equal +test-os-runs '(("open" "-R" "/a/b.pdf"))))
    (setq +test-os-runs nil)
    (let (asked)
      (cl-letf (((symbol-function '+my/os--reveal-dbus) (lambda (file) (push file asked) t)))
        (+test-on-linux (+my/os-reveal "/a/b.pdf")))
      (should (equal asked '("/a/b.pdf")))
      (should-not +test-os-runs))
    (+test-on-linux
      (+my/os-reveal "/a/b.pdf")
      (+my/os-reveal "/a/folder/"))
    (should (equal +test-os-runs '(("xdg-open" "/a/") ("xdg-open" "/a/"))))))

(ert-deftest os/reveal-through-dbus ()
  "The file manager asked on D-Bus for the file's URL; none answering: nil."
  (skip-unless (and (featurep 'dbusbind) (require 'dbus nil t)))
  (let (called)
    (cl-letf* (((symbol-function 'dbus-ping) (lambda (&rest _) t))
               ((symbol-function 'dbus-call-method-asynchronously)
                (lambda (&rest args) (setq called args))))
      (advice-remove '+my/os--reveal-dbus '+test-no-apps)
      (unwind-protect
          (should (+my/os--reveal-dbus "/a/it's #1.pdf"))
        (advice-add '+my/os--reveal-dbus :override #'ignore '((name . +test-no-apps)))))
    (should (equal (seq-take called 5)
                   '(:session "org.freedesktop.FileManager1" "/org/freedesktop/FileManager1"
                              "org.freedesktop.FileManager1" "ShowItems")))
    (should (equal (nth 6 called) (list :array (browse-url-file-url "/a/it's #1.pdf"))))
    (cl-letf (((symbol-function 'dbus-ping) (lambda (&rest _) nil)))
      (advice-remove '+my/os--reveal-dbus '+test-no-apps)
      (unwind-protect
          (should-not (+my/os--reveal-dbus "/a/b.pdf"))
        (advice-add '+my/os--reveal-dbus :override #'ignore '((name . +test-no-apps)))))))

(ert-deftest os/run-needs-the-program-on-linux ()
  "Linux: a program not installed is said (xdg-open, from xdg-utils); macOS's
open always is."
  (advice-remove '+my/os--run '+test-no-apps)
  (unwind-protect
      (+test-os--recording-calls
        (+test-os--with-programs '()
          (+test-on-linux
            (should-error (+my/os--run "xdg-open" "/a") :type 'user-error))
          (+test-on-macos (+my/os--run "open" "-R" "/a")))
        (+test-os--with-programs '("xdg-open")
          (+test-on-linux (+my/os--run "xdg-open" "/a")))
        ;; Not waited for (BUFFER 0).
        (should (equal calls '(("xdg-open" nil "/a") ("open" nil "-R" "/a")))))
    (advice-add '+my/os--run :override
                (lambda (program &rest args) (push (cons program args) +test-os-runs) 0)
                '((name . +test-no-apps)))))

;; ====== PRINTING ======

(ert-deftest os/print-on-macos-in-previews-dialog ()
  (let (made)
    (cl-letf (((symbol-function 'make-process) (lambda (&rest args) (setq made args) 'fake)))
      (+test-on-macos (+my/os-print "/a/print \"me\".pdf")))
    (let ((command (plist-get made :command)))
      (should (equal (car command) "osascript"))
      ;; The file an argument, not in the script.
      (should (equal (car (last command)) "/a/print \"me\".pdf"))
      (should (member "tell application \"Preview\"" command)))))

(ert-deftest os/print-on-linux-asks-then-lp ()
  "Linux: lp, on the default printer, once asked; no lp: said."
  (+test-os--recording-calls
    (+test-on-linux
      (+test-os--with-programs '()
        (should-error (+my/os-print "/a/b.pdf") :type 'user-error))
      (+test-os--with-programs '("lp")
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
          (+my/os-print "/a/b.pdf"))
        (should-not calls)
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (should (string-search "b.pdf" prompt)) t)))
          (+my/os-print "/a/-b.pdf")
          (should (equal calls '(("lp" nil "--" "/a/-b.pdf"))))
          (setq status 1)
          (should-error (+my/os-print "/a/b.pdf") :type 'user-error))))))

;; ====== THE CLIPBOARD'S IMAGES ======

(ert-deftest os/copy-image-on-macos ()
  (+test-os--recording-calls
    (+test-on-macos
      (+my/os-copy-image "/a/b.png" 'png)
      (+my/os-copy-image "/a/b.jpg" 'jpeg))
    (should (equal (car (nth 1 calls)) "osascript"))
    (should (member "set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)" (nth 1 calls)))
    (should (member "set the clipboard to (read (POSIX file (item 1 of argv)) as «class JPEG»)" (nth 0 calls)))
    (should (equal (car (last (nth 0 calls))) "/a/b.jpg"))
    (setq status 1)
    (+test-on-macos (should-error (+my/os-copy-image "/a/b.png" 'png) :type 'user-error))))

(ert-deftest os/copy-image-on-linux ()
  "Wayland: wl-copy; X11: xclip; the file as their input, its type given;
neither: said which is needed."
  (+test-os--recording-calls
    (+test-on-linux
      (let ((process-environment (cons "WAYLAND_DISPLAY=wayland-0" process-environment)))
        (+test-os--with-programs '("wl-copy" "xclip")
          (+my/os-copy-image "/a/b.png" 'png))
        (should (equal (car calls) '("wl-copy" "/a/b.png" "--type" "image/png")))
        ;; Wayland without wl-copy: xclip (XWayland).
        (+test-os--with-programs '("xclip")
          (+my/os-copy-image "/a/b.jpg" 'jpeg))
        (should (equal (car calls) '("xclip" "/a/b.jpg" "-selection" "clipboard" "-t" "image/jpeg")))
        (+test-os--with-programs '()
          (should-error (+my/os-copy-image "/a/b.png" 'png) :type 'user-error)))
      (let ((process-environment (cons "WAYLAND_DISPLAY" process-environment)))
        (+test-os--with-programs '("wl-copy" "xclip")
          (+my/os-copy-image "/a/b.png" 'png))
        (should (equal (car calls) '("xclip" "/a/b.png" "-selection" "clipboard" "-t" "image/png")))
        (setq status 1)
        (+test-os--with-programs '("xclip")
          (should-error (+my/os-copy-image "/a/b.png" 'png) :type 'user-error))))))

;; ====== IMAGE EDITING ======

(ert-deftest os/imagemagick-command ()
  (+test-os--with-programs '("magick" "convert")
    (should (equal (+my/os-imagemagick) "/usr/bin/magick")))
  (+test-os--with-programs '("convert")
    (should (equal (+my/os-imagemagick) "/usr/bin/convert")))
  (+test-os--with-programs '()
    (should-not (+my/os-imagemagick))))

(ert-deftest os/image-transform-commands ()
  "macOS: sips. Linux: ImageMagick, the file written in place; without it,
said."
  (+test-os--recording-calls
    (+test-on-macos
      (dolist (transform '(rotate-right rotate-left flip-horizontal flip-vertical))
        (+my/os-image-transform "/a/i.png" transform)))
    (should (equal (reverse calls)
                   '(("sips" nil "-r" "90" "/a/i.png") ("sips" nil "-r" "270" "/a/i.png")
                     ("sips" nil "-f" "horizontal" "/a/i.png") ("sips" nil "-f" "vertical" "/a/i.png"))))
    (setq calls nil)
    (+test-on-linux
      (+test-os--with-programs '("convert")
        (dolist (transform '(rotate-right rotate-left flip-horizontal flip-vertical))
          (+my/os-image-transform "/a/i.png" transform)))
      (should (equal (reverse calls)
                     '(("/usr/bin/convert" nil "/a/i.png" "-rotate" "90" "/a/i.png")
                       ("/usr/bin/convert" nil "/a/i.png" "-rotate" "270" "/a/i.png")
                       ("/usr/bin/convert" nil "/a/i.png" "-flop" "/a/i.png")
                       ("/usr/bin/convert" nil "/a/i.png" "-flip" "/a/i.png"))))
      (+test-os--with-programs '()
        (should-error (+my/os-image-transform "/a/i.png" 'rotate-right) :type 'user-error))
      (setq status 1)
      (+test-os--with-programs '("magick")
        (should-error (+my/os-image-transform "/a/i.png" 'rotate-right) :type 'user-error)))
    (should-error (+my/os-image-transform "/a/i.png" 'twirl))))

(ert-deftest os/image-transform-for-real-with-imagemagick ()
  "Linux's way, with the ImageMagick installed: a 3×2 picture rotated is
2×3, flipped stays 3×2."
  (skip-unless (+my/os-imagemagick))
  (let ((file (+test-os--png "real.png" 3 2)))
    (+test-on-linux (+my/os-image-transform file 'rotate-right))
    (should (equal (+test-os--size file) '(2 3)))
    (+test-on-linux (+my/os-image-transform file 'flip-vertical))
    (should (equal (+test-os--size file) '(2 3)))))

(ert-deftest os/image-to-png ()
  "macOS: sips, else ImageMagick (an SVG); Linux: ImageMagick; nil if
neither made it."
  (let ((to (+test-tmp-file "os/to.png")))
    (cl-letf (((symbol-function 'file-exists-p) (lambda (file) (equal file to))))
      (+test-os--recording-calls
        (+test-on-macos (should (+my/os-image-to-png "/a/b.tiff" to)))
        (should (equal calls `(("sips" nil "-s" "format" "png" "/a/b.tiff" "--out" ,to))))
        (setq calls nil)
        (+test-on-linux
          (+test-os--with-programs '("magick")
            (should (+my/os-image-to-png "/a/b.svg" to)))
          (should (equal calls `(("/usr/bin/magick" nil "/a/b.svg" ,(concat "png:" to)))))
          (+test-os--with-programs '()
            (should-not (+my/os-image-to-png "/a/b.svg" to))))
        ;; macOS, sips failing: ImageMagick.
        (setq calls nil)
        (cl-letf (((symbol-function 'call-process)
                   (lambda (program &rest args) (push (cons program args) calls)
                     (if (equal program "sips") 1 0))))
          (+test-on-macos
            (+test-os--with-programs '("magick")
              (should (+my/os-image-to-png "/a/b.svg" to)))))
        (should (equal (mapcar #'car calls) '("/usr/bin/magick" "sips")))))))

(ert-deftest os/image-to-png-for-real-with-imagemagick ()
  (skip-unless (+my/os-imagemagick))
  (let ((from (+test-os--png "from.gif" 4 3))
        (to (+test-tmp-file "os/made.png")))
    (+test-on-linux (should (+my/os-image-to-png from to)))
    (should (equal (+test-os--size to) '(4 3)))))

;; ====== DESKTOP NOTIFICATIONS ======

(ert-deftest os/notify-on-macos ()
  "Notification Center, through AppleScript in Emacs (posted as Emacs's);
quotes and backslashes escaped, line breaks spaces."
  (let ((+test-notifications nil))
    ;; macOS's Emacs has it, recorded (tests/helper.el); this test's Emacs may
    ;; be Linux's, without it.
    (cl-letf (((symbol-function 'do-applescript)
               (lambda (script) (push (list 'applescript script) +test-notifications) "")))
      (+test-on-macos
        (should (+my/os-notify "Claude Code" "doom: \"done\" in a\\b\nnext"))))
    (should (equal +test-notifications
                   '((applescript "display notification \"doom: \\\"done\\\" in a\\\\b next\" with title \"Claude Code\""))))))

(ert-deftest os/notify-on-macos-without-applescript-in-emacs ()
  "No `do-applescript' (an Emacs built without it): osascript's."
  (let ((+test-os-runs nil)
        (+test-notifications nil))
    (cl-letf (((symbol-function 'do-applescript) nil))
      (+test-on-macos (should (+my/os-notify "Title" "Body"))))
    (should-not +test-notifications)
    (should (equal +test-os-runs
                   '(("osascript" "-e" "display notification \"Body\" with title \"Title\""))))))

(ert-deftest os/notify-on-linux-through-dbus ()
  "The desktop's notifications (D-Bus): as Emacs's; a click runs the
caller's function."
  (let ((+test-notifications nil)
        (clicked nil))
    (cl-letf (((symbol-function '+my/os--dbus-notifications-p) (lambda () t)))
      (+test-on-linux
        (should (+my/os-notify "Claude Code" "doom: finished" (lambda () (setq clicked t))))
        (should (+my/os-notify "Claude Code" "no click"))))
    (pcase-let ((`((dbus . ,plain) (dbus . ,with-click)) +test-notifications))
      (should (equal (plist-get with-click :title) "Claude Code"))
      (should (equal (plist-get with-click :body) "doom: finished"))
      (should (equal (plist-get with-click :app-name) "Emacs"))
      (should (equal (plist-get with-click :actions) '("default" "Show")))
      (funcall (plist-get with-click :on-action) 1 "default")
      (should clicked)
      (should-not (plist-member plain :actions))
      (should-not (plist-member plain :on-action)))))

(ert-deftest os/notify-on-linux-without-dbus ()
  "No D-Bus notifications: notify-send; neither: none (nil)."
  (let ((+test-os-runs nil)
        (+test-notifications nil))
    (cl-letf (((symbol-function '+my/os--dbus-notifications-p) #'ignore))
      (+test-os--with-programs '("notify-send")
        (+test-on-linux (should (+my/os-notify "Title" "Body"))))
      (+test-os--with-programs '()
        (+test-on-linux (should-not (+my/os-notify "Title" "Body")))))
    (should-not +test-notifications)
    (should (equal +test-os-runs '(("notify-send" "--app-name=Emacs" "--icon=emacs" "Title" "Body"))))))
