;;; $DOOMDIR/config/stripe.el -*- lexical-binding: t; -*-
;; An error stripe at the right edge of file windows. Loaded from config.el;
;; its code is in config/stripe/.

;; ====== VARIABLES ======

;; ERROR STRIPE
;; A strip at the right edge of the window that maps the whole file onto the
;; window height, like marks on a scrollbar:
;; - flycheck diagnostics (LSP included): red errors, yellow warnings, dim
;;   yellow suggestions (flycheck's info: LSP hints, information; see
;;   `+my/stripe-diagnostic-levels');
;; - TODO comments: TODO, FIXME, HACK in blue (see `+my/stripe-todo-keywords');
;; - git changes (diff-hl), in the gutter's colours: red deleted, orange
;;   changed, green added;
;; - where several overlap, the most important wins, in that order
;;   (error > warning > TODO > deleted > changed > added > suggestion);
;; - a light band marks the part of the file on screen: the scrollbar's thumb.
;; Click the strip to jump to that part of the file; drag the band to scroll;
;; the wheel over it scrolls the file. On in every file buffer in prog, text and
;; conf modes (and so-long-mode).
;;
;; In graphical frames the strip is one image, drawn to the pixel, in a small
;; frame of its own (a child frame, as the notices' are) laid over the window's
;; right margin. It was a column of images in the margin, a slice per screen
;; row: every scroll changed every row's slice, so Emacs redrew every row
;; instead of moving the text (5.8 ms a step instead of 3.3), and rows had to be
;; measured (emoji, wrapped lines, smooth scrolling's part rows, the space
;; below the last line). Now the window's rows are left alone, and the image is
;; made anew only when it changes (most scrolls move the band by less than a
;; pixel). In a terminal each row is a coloured cell in the margin.

(defvar +my/stripe-diagnostic-levels '(error warning info)
  "Flycheck levels shown in the stripe: `error', `warning', `info' (suggestions:
LSP hints and information).")

(defvar +my/stripe-todo-keywords '("TODO" "FIXME" "HACK")
  "Keywords whose lines the stripe marks, as words, case matters: in code only
in comments, in text anywhere. nil: none.")

(defvar +my/stripe-mark-height 2
  "Height of a mark, in pixels (graphical frames): a line, as IntelliJ's, however
tall its line is on the strip. Marks of several lines (git hunks) span them,
this high at least.")

(defvar +my/stripe-thumb-min-height 12
  "Minimum height of the band, in pixels: big enough to grab (graphical frames).")

;; Windows with the stripe may scroll past the end of the file only a bit: at
;; most this much empty space below the last line. In graphical frames the
;; strip maps the file plus this space onto the whole window height, so it
;; never shrinks: the marks stay put as the end
;; comes into view, and the band reaches the bottom when the window can't
;; scroll further. In a terminal it covers only the rows with text.
(defvar +my/stripe-overscroll 0.25
  "How far windows with the stripe may scroll past the end of the buffer:
a fraction of the window height (float), a number of rows (integer), 0 for
none (the last line stops at the bottom), or t for no limit.")

;; PADDING
;; File windows (those with the stripe) get a character's width of space more
;; on each side of the text: their fringes are that much wider (8 -> 16 px).
;; What's drawn in them sits in the middle: the git gutter on the left, the
;; arrows of lines cut off at the edge and flycheck's on the right.
(defvar +my/stripe-padding 1
  "Columns of space added to each fringe of file windows (nil: none).")

;; In fringes 16 px wide flycheck switches to its big (16 px) markers: keep the
;; small ones, in the middle (Doom's slim arrow for errors and warnings).
(after! flycheck
  (when (fboundp 'define-fringe-bitmap)
    (define-fringe-bitmap 'flycheck-fringe-bitmap-double-arrow-hi-res
      [16 48 112 240 112 48 16] nil nil 'center)
    (define-fringe-bitmap 'flycheck-fringe-bitmap-fixable-hi-res
      flycheck-fringe-bitmap-fixable nil nil 'center)))

;; ====== KEY BINDINGS ======

(defvar +my/stripe-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [right-margin mouse-1] #'+my/stripe-jump)
    (define-key map [right-margin down-mouse-1] #'ignore)
    ;; The fringe next to the strip (see PADDING): a click there,
    ;; just short of the strip, does nothing (not "is undefined").
    (define-key map [right-fringe mouse-1] #'ignore)
    (define-key map [right-fringe down-mouse-1] #'ignore)
    map)
  "Keys in windows with the stripe (see `+my/stripe-mode').")

(defvar +my/stripe-margin-map
  (let ((map (make-sparse-keymap)))
    (define-key map [right-margin mouse-1] #'+my/stripe-jump)
    (define-key map [right-margin down-mouse-1] #'ignore)
    map)
  "Keymap on the stripe's margin strings (terminal). A keymap on the clicked
text wins over mode keymaps, e.g. outline-minor-mode's margin buttons.")

(defvar +my/stripe--strip-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'+my/stripe-press)
    (dolist (event '(mouse-1 drag-mouse-1 double-down-mouse-1 double-mouse-1
                     triple-down-mouse-1 triple-mouse-1 down-mouse-2 mouse-2
                     down-mouse-3 mouse-3))
      (define-key map (vector event) #'ignore))
    (dolist (event '(wheel-up wheel-down wheel-left wheel-right
                     double-wheel-up double-wheel-down triple-wheel-up triple-wheel-down))
      (define-key map (vector event) #'+my/stripe-wheel))
    map)
  "Keys on the strip's image (graphical frames).")

;; ====== CODE ======

;; In config/stripe/, in this order: each part can use what the ones before it
;; define, and the mode, last, turns the stripe on.
(load! "stripe/marks")
(load! "stripe/draw")
(load! "stripe/tty")
(load! "stripe/gui")
(load! "stripe/overscroll")
(load! "stripe/mouse")
(load! "stripe/mode")
