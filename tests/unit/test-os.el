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

(defmacro +test-os--really-running (&rest body)
  "BODY with `+my/os--run' running its programs (tests/helper.el only
records them)."
  (declare (indent 0))
  `(progn
     (advice-remove '+my/os--run '+test-no-apps)
     (unwind-protect (progn ,@body)
       (advice-add '+my/os--run :override
                   (lambda (program &rest args) (push (cons program args) +test-os-runs) 0)
                   '((name . +test-no-apps))))))

(ert-deftest os/run-needs-the-program-on-linux ()
  "Linux: a program not installed is said (xdg-open, from xdg-utils); macOS's
open always is."
  (+test-os--really-running
    (let ((made nil))
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest args) (push (plist-get args :command) made) nil)))
        (+test-os--with-programs '()
          (+test-on-linux
            (should-error (+my/os--run "xdg-open" "/a") :type 'user-error))
          (+test-on-macos (+my/os--run "open" "-R" "/a")))
        (+test-os--with-programs '("xdg-open")
          (+test-on-linux (+my/os--run "xdg-open" "/a"))))
      (should (equal made '(("xdg-open" "/a") ("open" "-R" "/a")))))))

(ert-deftest os/run-says-a-failure ()
  "Not waited for; failing (an exit status not 0), said once it ends, with
what it wrote (open: \"The file ... does not exist.\"), else its status.
Ending well: nothing said."
  (skip-unless (executable-find "sh"))
  (+test-os--really-running
    (+test-clear-messages)
    (let ((processes (+test-on-linux
                       (list (+my/os--run "sh" "-c" "echo 'The file /a does not exist.' >&2; exit 1")
                             (+my/os--run "sh" "-c" "exit 3")
                             (+my/os--run "sh" "-c" "echo fine")))))
      (should (seq-every-p #'processp processes))
      ;; Done: their output's buffers gone.
      (should (+test-wait-for (lambda ()
                                (not (seq-some (lambda (process) (buffer-live-p (process-buffer process)))
                                               processes)))
                              10)))
    (should (= (+test-messages "^sh failed: ") 2))
    (should (= (+test-messages "^sh failed: The file /a does not exist\\.$") 1))
    (should (= (+test-messages "^sh failed: exit status 3$") 1))
    (should (= (+test-messages "fine") 0))))

(ert-deftest os/a-file-on-another-machine ()
  "A remote file (TRAMP): no app here can open or show it, said; nothing
run."
  (let ((+test-os-runs nil))
    (dolist (system (list (lambda (f) (+test-on-macos (funcall f)))
                          (lambda (f) (+test-on-linux (funcall f)))))
      (funcall system
               (lambda ()
                 (should-error (+my/os-open "/ssh:host:/a/b.png") :type 'user-error)
                 (should-error (+my/os-reveal "/ssh:host:/a/b.png") :type 'user-error))))
    (+test-on-macos
      (should (equal (cadr (should-error (+my/os-open "/ssh:host:/a/b.png") :type 'user-error))
                     (format-message "Can't open a file on another machine in Preview: /ssh:host:/a/b.png")))
      (should (equal (cadr (should-error (+my/os-reveal "/ssh:host:/a/b.png") :type 'user-error))
                     (format-message "Can't show a file on another machine in Finder: /ssh:host:/a/b.png"))))
    (should-not +test-os-runs)))

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

;; ====== THE CLIPBOARD'S FILES ======

(ert-deftest os/file-url ()
  "A file's URL, each part of its path percent-encoded."
  (should (equal (+my/os-file-url "/tmp/a b#c.txt") "file:///tmp/a%20b%23c.txt"))
  (should (equal (+my/os-file-url "/tmp/ü.txt") "file:///tmp/%C3%BC.txt")))

(ert-deftest os/copy-file-on-macos ()
  "The file itself on the pasteboard, as Finder copies it: its URL written by
osascript's JavaScript; a folder too, without its slash. Not there, on another
machine, or not written (false): said."
  (let ((file (+test-tmp-file "os/copy/report.pdf")))
    (with-temp-file file (insert "%PDF"))
    (+test-os--recording-calls
      (+test-on-macos
        (+my/os-copy-file file)
        (+my/os-copy-file (file-name-directory file)))
      (should (equal (nth 1 calls) (list "osascript" nil "-l" "JavaScript" "-e" +my/os--copy-file-script file)))
      (should (equal (car (last (nth 0 calls))) (directory-file-name (file-name-directory file))))
      (should (string-search "writeObjects" +my/os--copy-file-script))
      (+test-on-macos
        (should-error (+my/os-copy-file (concat file ".gone")) :type 'user-error)
        (should-error (+my/os-copy-file "/ssh:host:/a/b.pdf") :type 'user-error)))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) (insert "false") 0)))
      (+test-on-macos
        (should (string-match-p "Couldn.t copy the file"
                                (cadr (should-error (+my/os-copy-file file) :type 'user-error))))))))

(ert-deftest os/copy-file-on-linux ()
  "Wayland: wl-copy; X11: xclip; the file's URL as a text/uri-list; neither:
said which is needed."
  (let ((file (+test-tmp-file "os/copy/a b.txt"))
        (region nil))
    (with-temp-file file (insert "x"))
    (+test-os--recording-calls
      (cl-letf (((symbol-function 'call-process-region)
                 (lambda (start end program &rest args)
                   (setq region (cons (buffer-substring start end) (cons program (nthcdr 3 args))))
                   status)))
        (+test-on-linux
          (let ((process-environment (cons "WAYLAND_DISPLAY=wayland-0" process-environment)))
            (+test-os--with-programs '("wl-copy" "xclip")
              (+my/os-copy-file file))
            (should (equal (car calls) (list "wl-copy" nil "--type" "text/uri-list"
                                             (concat (+my/os-file-url file) "\r\n"))))
            (should (string-search "a%20b.txt" (car (last (car calls))))))
          (let ((process-environment (cons "WAYLAND_DISPLAY" process-environment)))
            (+test-os--with-programs '("xclip")
              (+my/os-copy-file file))
            (should (equal region (list (concat (+my/os-file-url file) "\r\n")
                                        "xclip" "-selection" "clipboard" "-t" "text/uri-list")))
            (+test-os--with-programs '()
              (should (string-match-p "needs xclip"
                                      (cadr (should-error (+my/os-copy-file file) :type 'user-error)))))))))))

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
  "Notification Center, through AppleScript in Emacs (posted as Emacs's)
while it has a GUI display; quotes and backslashes escaped, line breaks
spaces."
  (let ((+test-notifications nil)
        (+test-os-runs nil))
    ;; macOS's Emacs has it, recorded (tests/helper.el); this test's Emacs may
    ;; be Linux's, without it, and has no display (batch).
    (cl-letf (((symbol-function 'do-applescript)
               (lambda (script) (push (list 'applescript script) +test-notifications) ""))
              ((symbol-function 'x-display-list) (lambda () '("Mac"))))
      (+test-on-macos
        (should (+my/os-notify "Claude Code" "doom: \"done\" in a\\b\nnext"))))
    (should (equal +test-notifications
                   '((applescript "display notification \"doom: \\\"done\\\" in a\\\\b next\" with title \"Claude Code\""))))
    (should-not +test-os-runs)))

(ert-deftest os/notify-on-macos-in-a-terminal ()
  "Emacs in a terminal (emacs -nw, a daemon with only terminal frames): its
AppleScript is there but errors without a GUI display; osascript's."
  (let ((+test-os-runs nil)
        (+test-notifications nil))
    (cl-letf (((symbol-function 'do-applescript)
               (lambda (_script) (error "Window system is not in use or not initialized")))
              ((symbol-function 'x-display-list) #'ignore))
      (+test-on-macos (should (+my/os-notify "Title" "Body"))))
    (should-not +test-notifications)
    (should (equal +test-os-runs
                   '(("osascript" "-e" "display notification \"Body\" with title \"Title\""))))))

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
  "No D-Bus notifications: notify-send, the title and body after --: one
starting with - isn't taken for an option; neither: none (nil)."
  (let ((+test-os-runs nil)
        (+test-notifications nil))
    (cl-letf (((symbol-function '+my/os--dbus-notifications-p) #'ignore))
      (+test-os--with-programs '("notify-send")
        (+test-on-linux
          (should (+my/os-notify "Title" "Body"))
          (should (+my/os-notify "Claude Code" "-1 test still failing"))))
      (+test-os--with-programs '()
        (+test-on-linux (should-not (+my/os-notify "Title" "Body")))))
    (should-not +test-notifications)
    (should (equal +test-os-runs
                   '(("notify-send" "--app-name=Emacs" "--icon=emacs" "--" "Claude Code" "-1 test still failing")
                     ("notify-send" "--app-name=Emacs" "--icon=emacs" "--" "Title" "Body"))))))
