;;; $DOOMDIR/config/image.el -*- lexical-binding: t; -*-
;; Images in Emacs's own viewer (image-mode), with a toolbar. Loaded from
;; config.el; its code is in config/image/.

;; ====== VARIABLES ======

;; IMAGES
;; Images open in Emacs's own viewer (image-mode) in the file's tab, in the
;; middle of the window (config/image/center.el), without a cursor, the tab's
;; header line a toolbar (as a PDF's page has one, config/pdf.el). Its buttons,
;; left to right, and their keys:
;;   ‹ 3/12 ›      J / K     the previous / next image in the folder (by name, as
;;                           people count: img2 before img10), in the same tab
;;   − 100% +      + / -     zoom (also Cmd+= / Cmd+-, Cmd+scroll, a pinch;
;;                           Linux: Ctrl+= / Ctrl+-, Ctrl+scroll)
;;   Fit           W         fit the window, scaled up too (it opens fitted if
;;                           bigger than the window, else at its size)
;;   1:1           0         its actual size (Cmd+0; Linux: Ctrl+0)
;;   ⟲ ⟳ ⇋ ⇵       R / r,    rotate anticlockwise / clockwise, flip
;;                 f / F     horizontally / vertically
;;   Crop          c         drag a rectangle, RET crops, q cancels (Emacs's
;;                           image-crop, with ImageMagick)
;;       Rotating, flipping and cropping change the image, as Preview does: the
;;       tab is modified, saved as any file (SPC f s, Cmd+S, the toolbar's Save)
;;       and undone by reverting it (SPC b r). Not SVGs (text), nor animations
;;       (one frame would be kept). With macOS's sips; on Linux ImageMagick.
;;   ▶ / ⏸         RET       an animation (GIF, WebP...) played / paused
;;   Sharp         SPC m s   no smoothing: pixels stay square zoomed in, for
;;                           screenshots and icons
;;   1600×900 · PNG · 412 kB  its size in pixels, type (frames) and file size
;;   Copy          y         the image itself to the clipboard (Cmd+C too;
;;                           Linux: Ctrl+Shift+C, with wl-copy or xclip), to
;;                           paste in Slack, GitHub...; SPC m y copies its path
;;   Diff          SPC m g   the image as it is in git's HEAD, to compare (e.g.
;;                           regenerated screenshots): the image's pane halved,
;;                           HEAD on the left (in a pane too narrow for two,
;;                           `+my/image-diff-min-width', above it), both fitted;
;;                           again, closed
;;   Save                    shown while edited (see above)
;;   Preview       SPC m p   open it in macOS's Preview; SPC m f shows it in
;;                           Finder (Linux: Open, its default app; Folder, the
;;                           file manager)
;; SPC m t turns the toolbar off (all images'); q closes the image. The
;; toolbar and Sharp are as the last image had them, the variables below for
;; the first. A narrow window's toolbar is never wider than it: it leaves out
;; the file's size, then puts in the menu of a … button (their keys said
;; there) Preview and Finder, the edits, Fit, 1:1 and Sharp, the folder's
;; ‹ n/m ›, zoom; Copy, Diff (HEAD shown) and Save (edited) last.
;; A file changed on disk (e.g. a regenerated screenshot) is shown anew, its
;; zoom kept: auto-revert-mode (not while edited and unsaved).
;; Where images don't show (a terminal), the file's text: none of this.
(defvar +my/image-toolbar t
  "Show the toolbar in the first image opened (see above).")

(defvar +my/image-sharp nil
  "No smoothing in the first image opened (see above).")

(defvar +my/image-zoom-step 1.25
  "How much + / - and Cmd+= / Cmd+- zoom an image (a factor).")

(defvar +my/image-zoom-limits '(0.05 . 20.0)
  "The smallest and largest zoom (1.0: the image's actual size).")

(defvar +my/image-diff-min-width 30
  "The narrowest the image and its HEAD version get side by side (SPC m g),
in columns each: a narrower pane has HEAD above the image.")

(defvar +my/image-mode-map (make-sparse-keymap)
  "Keys of images (see `+my/image-mode').")

;; ====== KEY BINDINGS ======

(map! :map +my/image-mode-map
      "s-="             #'+my/image-zoom-in
      "s-+"             #'+my/image-zoom-in
      "s--"             #'+my/image-zoom-out
      "s-0"             #'+my/image-actual-size
      "s-c"             #'+my/image-copy
      "C-<wheel-up>"    #'+my/image-zoom-in-mouse
      "C-<wheel-down>"  #'+my/image-zoom-out-mouse
      "s-<wheel-up>"    #'+my/image-zoom-in-mouse
      "s-<wheel-down>"  #'+my/image-zoom-out-mouse
      "<pinch>"         #'+my/image-pinch
      :n "J"   #'+my/image-next
      :n "K"   #'+my/image-previous
      :n "+"   #'+my/image-zoom-in
      :n "="   #'+my/image-zoom-in
      :n "-"   #'+my/image-zoom-out
      :n "W"   #'+my/image-fit
      :n "0"   #'+my/image-actual-size
      :n "r"   #'+my/image-rotate
      :n "R"   #'+my/image-rotate-left
      :n "f"   #'+my/image-flip
      :n "F"   #'+my/image-flip-vertically
      :n "c"   #'+my/image-crop
      :n "y"   #'+my/image-copy
      :n "RET" #'+my/image-toggle-animation
      :n "q"   #'kill-current-buffer)    ; as PDFs

;; On Linux, Ctrl for Cmd (config/emacs.el, KEYS): zoom, copy.
(map! :unless (+my/macos-p)
      :map +my/image-mode-map
      :n "C-="   #'+my/image-zoom-in
      :n "C-+"   #'+my/image-zoom-in
      :n "C--"   #'+my/image-zoom-out
      :n "C-0"   #'+my/image-actual-size
      :n "C-S-c" #'+my/image-copy)

(map! :map +my/image-mode-map
      :localleader
      :desc "Toolbar"                "t" #'+my/image-toggle-toolbar
      :desc "Diff with git's HEAD"   "g" #'+my/image-diff
      :desc "Sharp pixels"           "s" #'+my/image-toggle-sharp
      :desc "Crop"                   "c" #'+my/image-crop
      :desc "Copy the path"          "y" #'+my/image-copy-path
      :desc (concat "Open in " (+my/os-app-name 'viewer)) "p" #'+my/image-open-in-preview
      :desc (concat "Show in " (+my/os-app-name 'files))  "f" #'+my/image-show-in-finder)

;; ====== CODE ======

;; In config/image/, in this order: each part can use what the ones before it
;; define.
(load! "image/files")
(load! "image/commands")
(load! "image/edit")
(load! "image/diff")
(load! "image/center")
(load! "image/toolbar")
(load! "image/mode")
