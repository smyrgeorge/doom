;;; scripts/screenshots.el -*- lexical-binding: t; -*-
;; The GUI Emacs scripts/screenshots.sh runs (after tests/helper.el: Doom's
;; packages, its own temp folders; your Doom profile and a running Emacs
;; aren't touched). This config's look (doom-one, JetBrains Mono, Doom's mode
;; line), a frame on top of the others; each example opened, the frame
;; captured with macOS's screencapture into DIR/NAME.png, the example closed.
;; Its progress, lines starting with "screenshots:", on stderr; exit status 0
;; if each was captured. See docs/examples.md.

(defvar +my/screenshots-size '(1200 . 860)
  "The frame's text area in pixels, at most (the screen's work area less a
margin otherwise). Narrow, so GitHub, which fits images to its ~880 px README
column, shrinks the text little.")

(defvar +my/screenshots-wait 1.5
  "Seconds an example is given to be drawn (and composited) before it's
captured; after `+my/example-NAME-ready' says it is, where it has one.")

(defvar +my/screenshots-ready-timeout 40
  "Seconds an example with `+my/example-NAME-ready' is given to get ready.")

(defun +my/screenshots--say (format-string &rest args)
  "A progress line on stderr: \"screenshots: \" and FORMAT-STRING with ARGS."
  (princ (concat "screenshots: " (apply #'format format-string args) "\n")
         #'external-debugging-output))

(defun +my/screenshots--names ()
  "The examples to capture: SCREENSHOT_EXAMPLES (names, space-separated), or
all of them."
  (or (split-string (or (getenv "SCREENSHOT_EXAMPLES") "") " " t)
      (+my/examples)))

(defun +my/screenshots--setup ()
  "This config's look. Doom's frame too, which `emacs -Q' hasn't: no tool bar
\(its icons were in the title bar), no scroll bars, no cursor in the windows
not selected (a hollow box in the panes), a cursor that doesn't blink."
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
  ;; A cursor that doesn't blink, as Doom's: captured blinked out or not, the
  ;; screenshot changed at each run.
  (blink-cursor-mode -1)
  (setq-default cursor-in-non-selected-windows nil)
  (let ((build (file-name-directory
                (directory-file-name (file-name-directory (locate-library "magit"))))))
    (dolist (package '("magit" "magit-section" "diff-hl"))
      (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))
  (require 'doom-themes)
  (+test-load "config/childframe" "config/banner" "config/window" "config/editor"
              "config/webkit" "config/pdf" "config/markdown" "config/excalidraw"
              "config/stripe" "config/tiling" "config/merge" "config/examples")
  ;; PDF.js and Excalidraw: copies of Doom's, not downloaded again.
  (+test-pdfjs-dir)
  (+test-excalidraw-dir)
  ;; As Doom has them: line numbers in code, text and conf buffers; the
  ;; current line in every window; the git gutter (its ui/vc-gutter +pretty:
  ;; thin bars in the left fringe, flycheck's arrows in the right).
  (setq-default display-line-numbers-type t
                display-line-numbers-width 3
                display-line-numbers-widen t)
  (dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
    (add-hook hook #'display-line-numbers-mode))
  (require 'hl-line)
  (setq global-hl-line-sticky-flag 'window)
  (global-hl-line-mode 1)
  (+test-load-module :ui 'vc-gutter)
  (when (require 'diff-hl nil t)
    (global-diff-hl-mode 1))
  (global-so-long-mode 1)
  (require 'markdown-mode)              ; *.md in it (its autoloads)
  (unless (bound-and-true-p markdown-css-paths)
    (setq markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css/github-markdown.min.css")))
  (load-theme 'doom-one t)
  (run-hooks 'doom-load-theme-hook)
  (when (find-font (font-spec :family "JetBrains Mono"))
    (set-frame-font (font-spec :family "JetBrains Mono" :size 13) nil t))
  (when (require 'doom-modeline nil t)
    (doom-modeline-mode 1))
  (global-tab-line-mode 1))

(defun +my/screenshots--place (frame)
  "FRAME as large as `+my/screenshots-size' allows on its screen, near its top
left corner, above the other windows, focused."
  (pcase-let ((`(,x ,y ,width ,height) (frame-monitor-workarea frame)))
    (set-frame-parameter frame 'fullscreen nil)
    (set-frame-parameter frame 'z-group 'above)
    (set-frame-size frame
                    (min (car +my/screenshots-size) (- width 80))
                    (min (cdr +my/screenshots-size) (- height 120))
                    t)
    (set-frame-position frame (+ x 40) (+ y 40))
    (select-frame-set-input-focus frame)))

;; THE FRAME'S WINDOW
;; Captured as a window (screencapture -l), not as the screen's rectangle under
;; it: its rounded corners black, not what was behind it (the desktop,
;; other apps), which changed every screenshot's corners at each run, the
;; example unchanged. No shadow (-o). Its macOS window number isn't Emacs's
;; (`window-id' is "1"): asked of macOS's window list (JavaScript for
;; Automation, CoreGraphics), this Emacs's windows, the one where the frame is:
;; at any level (the frame is above the others, `+my/screenshots--place':
;; level 1, not the usual 0), among its child frames' (the stripe's...).
(defconst +my/screenshots--windows-script
  "ObjC.import('CoreGraphics');
function run(argv) {
  const list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
  const lines = [];
  for (let i = 0; i < list.count; i++) {
    const w = ObjC.deepUnwrap(list.objectAtIndex(i));
    if (w.kCGWindowOwnerPID == argv[0]) {
      const b = w.kCGWindowBounds;
      lines.push([w.kCGWindowNumber, b.X, b.Y, b.Width, b.Height].join(' '));
    }
  }
  return lines.join('\\n');
}"
  "Prints this Emacs's windows on screen (its pid the argument): a line each,
\"NUMBER X Y WIDTH HEIGHT\".")

(defun +my/screenshots--window-number (frame)
  "FRAME's macOS window number (see above), or nil if macOS doesn't say."
  (pcase-let* ((`(,left ,top ,right ,bottom) (frame-edges frame 'outer-edges))
               (windows
                (with-temp-buffer
                  (and (eql 0 (call-process "osascript" nil '(t nil) nil
                                            "-l" "JavaScript"
                                            "-e" +my/screenshots--windows-script
                                            (number-to-string (emacs-pid))))
                       (mapcar (lambda (line) (mapcar #'string-to-number (split-string line)))
                               (split-string (buffer-string) "\n" t))))))
    (car (or (seq-find (lambda (window)
                         (equal (cdr window) (list left top (- right left) (- bottom top))))
                       windows)
             ;; Its edges not quite macOS's: this Emacs's only window.
             (and (= (length windows) 1) (car windows))))))

;; THE SAME SCREENSHOT
;; macOS draws the window's outer edge (its 1 px border, its rounded corners'
;; curve) a little differently from one capture to the next, and WebKit a few
;; pixels a shade apart (PDF.js's toolbar): the example unchanged, its
;; screenshot's file changed at each run. A new capture differing from the
;; last screenshot only there leaves the last one as it is: its outer
;; `+my/screenshots-edge' pixels and its corners' `+my/screenshots-corner'
;; squares left out, colours within `+my/screenshots-fuzz' the same. Not more
;; of the edge: the error stripe's marks are in the window's last 10 pixels.
;; With ImageMagick (scripts/tools.sh); without it, each capture replaces it.
(defvar +my/screenshots-edge 3
  "Pixels on each side of a screenshot (the window's border) a new capture may
differ in from the last one and still be the same screenshot (see above).")

(defvar +my/screenshots-corner 12
  "The side of the squares, at a screenshot's corners within its edge, a new
capture may differ in (the rounded corners' curve, see above).")

(defvar +my/screenshots-fuzz "1%"
  "How far apart two pixels' colours may be and still be the same (see
above): ImageMagick's -fuzz.")

(defun +my/screenshots--same-p (old new)
  "Non-nil if image files OLD and NEW are the same but for their edge and
corners, colours within the fuzz (see above); nil without ImageMagick."
  (and (executable-find "magick")
       (with-temp-buffer
         (and (eql 0 (apply #'call-process "magick" nil t nil old new
                            "-alpha" "off"
                            "-shave" (format "%dx%d" +my/screenshots-edge +my/screenshots-edge)
                            "-fill" "black"
                            (append
                             ;; The corners blacked out in both: top left, top
                             ;; right, bottom left, bottom right (%[fx:w] and
                             ;; %[fx:h], ImageMagick's: the image's size).
                             (let ((c +my/screenshots-corner)
                                   (n (1- +my/screenshots-corner)))
                               (mapcan (lambda (rectangle) (list "-draw" (concat "rectangle " rectangle)))
                                       (list (format "0,0 %d,%d" n n)
                                             (format "%%[fx:w-%d],0 %%[fx:w],%d" c n)
                                             (format "0,%%[fx:h-%d] %d,%%[fx:h]" c n)
                                             (format "%%[fx:w-%d],%%[fx:h-%d] %%[fx:w],%%[fx:h]" c c))))
                             (list "-fuzz" +my/screenshots-fuzz
                                   "-metric" "AE" "-compare"
                                   "-format" "%[distortion]" "info:"))))
              (let ((said (string-trim (buffer-string))))
                (and (string-match-p "\\`[0-9.e+-]+\\'" said)
                     (zerop (string-to-number said))))))))

(defun +my/screenshots--capture (frame file)
  "Capture FRAME's window (the title bar too, no shadow, its corners
black: see above) into FILE (a PNG), with SCREENCAPTURE (default:
macOS's screencapture); the screen's rectangle under it if macOS didn't say
which window it is. t if captured, else why not (what screencapture said,
its exit status). Captured into a temp file first: FILE (the last
screenshot) replaced only by a capture made, not lost when it fails (e.g.
without the Screen Recording permission), and not by one the same but for
the window's edge (see THE SAME SCREENSHOT)."
  (pcase-let ((`(,left ,top ,right ,bottom) (frame-edges frame 'outer-edges))
              (number (+my/screenshots--window-number frame))
              (new (concat (file-name-sans-extension file) ".new.png")))
    (when (file-exists-p new)
      (delete-file new))
    (with-temp-buffer
      (let ((status (apply #'call-process (or (getenv "SCREENCAPTURE") "screencapture") nil t nil
                           (append
                            '("-x" "-t" "png")
                            (if number
                                (list "-o" "-l" (number-to-string number))
                              (list "-R" (format "%d,%d,%d,%d" left top (- right left) (- bottom top))))
                            (list new))))
            (said (string-trim (buffer-string))))
        (if (and (eql status 0) (file-exists-p new))
            (progn (if (and (file-exists-p file) (+my/screenshots--same-p file new))
                       (delete-file new)
                     (rename-file new file t))
                   t)
          (when (file-exists-p new)
            (delete-file new))
          (string-join (delq nil (list (and (not (string-empty-p said)) said)
                                       (format "exit %s" status)
                                       (and (eql status 0) "no file made")))
                       ", "))))))

(defun +my/screenshots--close ()
  "Close what an example opened: its merges aborted (its files go with them),
one window on *scratch* again, the echo area empty: a message of two lines
left the next example's panes laid out around a taller echo area (tiling's,
after stripe's), its screenshot changed with the message before it."
  (dolist (buffer (buffer-list))
    (when-let* (((buffer-live-p buffer))
                (session (buffer-local-value '+my/merge--session buffer)))
      (ignore-errors (+my/merge--finish session))))
  (+test-reset)
  (message nil)
  (redisplay t))

(defun +my/screenshots--one (name dir)
  "Open example NAME, capture it into DIR/NAME.png, close it. Non-nil if it
was captured."
  (let ((file (expand-file-name (concat name ".png") dir)))
    (+test-reset)
    (unwind-protect
        (condition-case err
            (progn
              (call-interactively (intern (format "+my/example-%s" name)))
              (let ((ready (intern (format "+my/example-%s-ready" name))))
                (when (and (fboundp ready)
                           (not (+test-wait-for ready +my/screenshots-ready-timeout)))
                  (error "Not drawn after %d s (%s)" +my/screenshots-ready-timeout ready)))
              (+test-sleep +my/screenshots-wait)
              (let ((captured (+my/screenshots--capture (selected-frame) file)))
                (if (eq captured t)
                    (progn (+my/screenshots--say "%s" file) t)
                  (+my/screenshots--say
                   "%s: not captured (screencapture: %s). The terminal running this needs the Screen Recording permission (System Settings > Privacy & Security > Screen & System Audio Recording), and to be restarted after it's given."
                   name captured)
                  nil)))
          (error (+my/screenshots--say "%s: %s" name (error-message-string err))
                 nil))
      (+my/screenshots--close))))

(defun +my/screenshots-run ()
  "Capture the examples (see `+my/screenshots--names') into SCREENSHOT_DIR
\(default: examples/), then exit: 0 if each was captured."
  ;; Never left running.
  (run-at-time 600 nil #'kill-emacs 3)
  ;; Once the GUI frame is up.
  (run-at-time
   0.5 nil
   (lambda ()
     (let ((dir (or (getenv "SCREENSHOT_DIR") +my/examples-dir))
           (ok nil))
       (condition-case err
           (progn
             (+my/screenshots--setup)
             (+my/screenshots--place (selected-frame))
             (+test-sleep 0.5)
             (setq ok t)
             (dolist (name (+my/screenshots--names))
               (unless (+my/screenshots--one name dir)
                 (setq ok nil))))
         (error (+my/screenshots--say "%s" (error-message-string err))
                (setq ok nil)))
       (kill-emacs (if ok 0 1))))))

(provide 'screenshots)
