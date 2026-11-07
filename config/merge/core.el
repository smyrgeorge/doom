;;; $DOOMDIR/config/merge/core.el -*- lexical-binding: t; -*-
;; What the parts share: a merge, its changes, the panes' mode. Loaded from
;; config/merge.el.

(cl-defstruct (+my/merge (:constructor +my/merge--make) (:copier nil))
  "A file being resolved."
  path toplevel coding labels frame
  yours base theirs result bar          ; buffers
  chunks                                ; vector of `+my/merge-chunk'
  winconf finished)

(cl-defstruct (+my/merge-chunk (:constructor +my/merge-chunk--make) (:copier nil))
  "A change (a region where a side differs from the base)."
  index
  kind                                  ; conflict, yours, theirs, same
  yours theirs result                   ; overlays in those buffers
  base                                  ; the base's text there
  yours-state theirs-state              ; nil, applied, ignored, merged
  wand                                  ; the sides' words merged, if they can be
  order                                 ; the sides applied, first first
  buttons)                              ; overlays of its margin buttons

(defvar-local +my/merge--session nil
  "The merge the buffer is part of (all its panes and the bar).")

(defvar +my/merge--aligning nil
  "Non-nil while fillers are made (not changes to line up after, see LINING
UP in config/merge/align.el).")

(define-minor-mode +my/merge-mode
  "A pane of a merge (see config/merge.el).

\\{+my/merge-mode-map}"
  :keymap +my/merge-mode-map
  (if +my/merge-mode
      (setq-local hl-line-range-function #'+my/merge--hl-line-range)
    (kill-local-variable 'hl-line-range-function)))

(defun +my/merge--hl-line-range ()
  "The current line's highlight (hl-line's range) in a pane: none on a
change's coloured lines. Doom's current line (`global-hl-line-sticky-flag'
window) shows in every window, above the changes' colours (its overlay's
priority is the selection's, which they stay under): the first change, where
each pane's point starts, looked like no change."
  (let ((start (line-beginning-position))
        (end (line-beginning-position 2)))
    (if (seq-some (lambda (ov) (and (memq (overlay-get ov 'face)
                                          '(+my/merge-changed +my/merge-added
                                            +my/merge-removed +my/merge-conflict))
                                    (< (overlay-start ov) (overlay-end ov))))
                  (overlays-in start end))
        (cons start start)
      (cons start end))))
