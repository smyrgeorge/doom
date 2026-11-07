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
not selected (a hollow box in the panes)."
  (tool-bar-mode -1)
  (scroll-bar-mode -1)
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

(defun +my/screenshots--capture (frame file)
  "Capture FRAME (its outer edges: the title bar too) into FILE (a PNG), with
SCREENCAPTURE (default: macOS's screencapture). t if FILE was made, else why
not (what screencapture said, its exit status)."
  (pcase-let ((`(,left ,top ,right ,bottom) (frame-edges frame 'outer-edges)))
    (when (file-exists-p file)
      (delete-file file))
    (with-temp-buffer
      (let ((status (call-process (or (getenv "SCREENCAPTURE") "screencapture") nil t nil
                                  "-x" "-t" "png"
                                  "-R" (format "%d,%d,%d,%d" left top (- right left) (- bottom top))
                                  file))
            (said (string-trim (buffer-string))))
        (if (and (eql status 0) (file-exists-p file))
            t
          (string-join (delq nil (list (and (not (string-empty-p said)) said)
                                       (format "exit %s" status)
                                       (and (eql status 0) "no file made")))
                       ", "))))))

(defun +my/screenshots--close ()
  "Close what an example opened: its merges aborted (its files go with them),
one window on *scratch* again."
  (dolist (buffer (buffer-list))
    (when-let* (((buffer-live-p buffer))
                (session (buffer-local-value '+my/merge--session buffer)))
      (ignore-errors (+my/merge--finish session))))
  (+test-reset))

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
