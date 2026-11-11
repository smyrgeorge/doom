;;; $DOOMDIR/config/editor/minibuffer.el -*- lexical-binding: t; -*-
;; A minibuffer left open while you're elsewhere, in the theme's colours.
;; Loaded from config/editor.el.

;; A MINIBUFFER LEFT OPEN
;; Emacs 31 marks a minibuffer still waiting while another window is selected
;; (`minibuffer-nonselected-mode', on): its prompt and input in the face
;; `minibuffer-nonselected', bold dark red on bright yellow, which Doom's
;; themes don't set. A soft tint of the theme's yellow instead, blended into
;; its background, the prompt and the input in their own colours: still
;; plainly a minibuffer waiting. Where colours are true (the GUI, a terminal
;; with 24-bit colour); with 256, the palette's nearest tint (a light theme's:
;; lightest); with fewer, the region's colours. Set again on each theme: its
;; colours, not a frame's (as config/merge/theme.el). How much yellow:
;; `+my/minibuffer-nonselected-tint' (config/editor.el). Set as the face's
;; override, over Emacs's own: what that sets and this doesn't (its
;; foreground, its weight) said to be unspecified, or they'd stay.
(defun +my/minibuffer-faces-h ()
  "The minibuffer left open in the theme's colours (see above)."
  (when (and (facep 'minibuffer-nonselected) (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (doom-color 'bg))
          (yellow (doom-color 'yellow)))
      (when (and (stringp bg) (string-prefix-p "#" bg)
                 (stringp yellow) (string-prefix-p "#" yellow))
        (face-spec-set
         'minibuffer-nonselected
         `((((min-colors 257))
            :background ,(doom-blend yellow bg +my/minibuffer-nonselected-tint)
            :foreground unspecified :weight unspecified)
           (((min-colors 256))
            :background ,(if (color-dark-p (color-name-to-rgb bg)) "#5f5f00" "#ffffd7")
            :foreground unspecified :weight unspecified)
           (t :inherit region :background unspecified :foreground unspecified
              :weight unspecified)))))))

(+my/minibuffer-faces-h)
(add-hook 'doom-load-theme-hook #'+my/minibuffer-faces-h)
