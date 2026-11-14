;;; $DOOMDIR/config/merge/panes.el -*- lexical-binding: t; -*-
;; The changes in the panes, with their buttons. Loaded from config/merge.el.

;; PANES
;; The sides' changes highlighted, with their buttons in the margin by the
;; Result (Yours: its right one, Theirs: its left one); the Result's
;; highlighted until done.
(defun +my/merge--face (chunk side)
  "The face of SIDE's region (yours, theirs, result) of CHUNK."
  (cond ((eq side 'result)
         (unless (+my/merge--resolved-p chunk)
           (if (eq (+my/merge-chunk-kind chunk) 'conflict) '+my/merge-conflict '+my/merge-changed)))
        ((not (+my/merge--changed-p chunk side)) nil)
        ((+my/merge--handled-p chunk side) '+my/merge-done)
        ((eq (+my/merge-chunk-kind chunk) 'conflict) '+my/merge-conflict)
        ((= (overlay-start (+my/merge--overlay chunk side)) (overlay-end (+my/merge--overlay chunk side)))
         '+my/merge-removed)
        ((string-empty-p (+my/merge-chunk-base chunk)) '+my/merge-added)
        (t '+my/merge-changed)))

(defun +my/merge--icon (name fallback)
  "Nerd icon NAME in the GUI, FALLBACK in a terminal."
  (or (and (display-graphic-p) (require 'nerd-icons nil t)
           (ignore-errors
             (if (string-prefix-p "nf-md-" name) (nerd-icons-mdicon name) (nerd-icons-codicon name))))
      fallback))

(defun +my/merge--button (label action chunk side help)
  "A button LABEL in a margin: ACTION (applied, ignored) of SIDE in CHUNK."
  (let ((label (copy-sequence label)))
    (add-face-text-property 0 (length label) '+my/merge-button t label)
    (add-text-properties 0 (length label)
                         (list '+my/merge-action (list chunk side action)
                               'mouse-face 'highlight 'help-echo help
                               ;; The hand, should Emacs show it there: its
                               ;; mouse code puts the arrow back over a margin
                               ;; (xdisp.c, Bug#16647); the bar's show it.
                               'pointer 'hand)
                         label)
    label))

(defun +my/merge--buttons (chunk side)
  "The margin text of SIDE's change in CHUNK: its buttons while not done."
  (let ((other (+my/merge--other side)))
    (cond ((not (+my/merge--changed-p chunk side)) nil)
          ((+my/merge--state chunk side)
           (propertize (pcase (+my/merge--state chunk side)
                         ('applied (+my/merge--icon "nf-cod-check" "ok"))
                         ('merged (+my/merge--icon "nf-cod-wand" "*"))
                         (_ " "))
                       'face '+my/merge-done))
          (t
           (+my/merge--pair chunk side
                            (if (and (eq (+my/merge-chunk-kind chunk) 'conflict)
                                     (eq (+my/merge--state chunk other) 'applied))
                                (format "Add after %s's (keep both)" (if (eq other 'yours) "Yours" "Theirs"))
                              "Put in the Result"))))))

(defun +my/merge--pair (chunk side apply-help)
  "SIDE's two buttons for CHUNK: put in the Result (APPLY-HELP its help),
ignore; Yours' in that order, Theirs' the other way."
  (let ((apply (+my/merge--button
                (if (eq side 'yours)
                    (+my/merge--icon "nf-md-chevron_double_right" ">>")
                  (+my/merge--icon "nf-md-chevron_double_left" "<<"))
                'applied chunk side apply-help))
        (ignore (+my/merge--button (+my/merge--icon "nf-cod-close" "x")
                                   'ignored chunk side "Ignore")))
    (if (eq side 'yours) (concat apply " " ignore) (concat ignore " " apply))))

(defvar +my/merge-margin-map
  (let ((map (make-sparse-keymap)))
    (define-key map [left-margin mouse-1] #'+my/merge-click)
    (define-key map [right-margin mouse-1] #'+my/merge-click)
    (define-key map [left-margin down-mouse-1] #'ignore)
    (define-key map [right-margin down-mouse-1] #'ignore)
    map)
  "Clicks on the margins' strings (the buttons, the wand). On the strings
themselves: a keymap there comes before every mode's (minor modes', Evil's),
and Doom's debugger's dap-mode binds a click in the left margin (a
breakpoint) in code buffers, which took Theirs' buttons and the wand's.")

(defun +my/merge--margin-string (text)
  "TEXT for a margin, its clicks the merge's (see `+my/merge-margin-map')."
  (propertize text 'keymap +my/merge-margin-map))

(defconst +my/merge--margin-columns 5
  "The width of Theirs' margin (its buttons'), in columns; Yours' in a
terminal (see `+my/merge--yours-margin-columns').")

(defun +my/merge--margin-fit (text columns)
  "COLUMNS, or in the GUI the columns TEXT's pixels take if more: a margin is
counted in the default font's columns, the buttons' icons are another font's,
as wide as that one makes them (wider than 6 columns of a 7-pixel font: the x
cut off)."
  (if (display-graphic-p)
      (max columns (ceiling (string-pixel-width text) (frame-char-width)))
    columns))

(defun +my/merge--theirs-margin-columns ()
  "The width of Theirs' (left) margin, in columns: its buttons'."
  (+my/merge--margin-fit (+my/merge--pair nil 'theirs "") +my/merge--margin-columns))

(defun +my/merge--yours-margin-columns ()
  "The width of Yours' (right) margin, in columns: Theirs', and in the GUI
one more for the space before the buttons (see
`+my/merge--right-margin-text'), the icons being wider than a column; more if
its buttons take more."
  (+my/merge--margin-fit (+my/merge--right-margin-text (+my/merge--pair nil 'yours ""))
                         (if (display-graphic-p) (1+ +my/merge--margin-columns) +my/merge--margin-columns)))

(defun +my/merge--right-margin-text (text)
  "TEXT for Yours' (right) margin: after a space. Left-aligned in the margin,
the buttons touched the code, where Theirs' are a few pixels from it. In a
terminal it also keeps the margin's first column blank: a click there comes
as one on the text (posn-at-x-y, Emacs 31). A space, not a narrower stretch:
a space display spec in a margin's string is drawn a column wide."
  (concat " " text))

(defun +my/merge--render-chunk (chunk)
  "Show CHUNK's state in the three panes."
  (dolist (side '(yours theirs result))
    (overlay-put (+my/merge--overlay chunk side) 'face (+my/merge--face chunk side)))
  (mapc #'delete-overlay (+my/merge-chunk-buttons chunk))
  (setf (+my/merge-chunk-buttons chunk) nil)
  (dolist (side '(yours theirs))
    (when-let* ((text (+my/merge--buttons chunk side)))
      (let* ((region (+my/merge--overlay chunk side))
             (ov (make-overlay (overlay-start region) (overlay-start region) (overlay-buffer region))))
        (overlay-put ov 'before-string
                     (propertize " " 'display
                                 (if (eq side 'yours)
                                     `((margin right-margin)
                                       ,(+my/merge--margin-string (+my/merge--right-margin-text text)))
                                   `((margin left-margin) ,(+my/merge--margin-string text)))))
        (push ov (+my/merge-chunk-buttons chunk)))))
  ;; The wand, in the Result's margin, while it can merge.
  (when (and (+my/merge-chunk-wand chunk) (not (+my/merge--resolved-p chunk)))
    (let* ((region (+my/merge-chunk-result chunk))
           (ov (make-overlay (overlay-start region) (overlay-start region) (overlay-buffer region))))
      (overlay-put ov 'before-string
                   (propertize " " 'display
                               `((margin left-margin)
                                 ,(+my/merge--margin-string
                                   (+my/merge--button (+my/merge--icon "nf-cod-wand" "*")
                                                      'merged chunk 'both
                                                      "Merge the words both sides changed (wand)")))))
      (push ov (+my/merge-chunk-buttons chunk))))
  ;; A change with nothing in the Result: a mark in its fringe.
  (let ((region (+my/merge-chunk-result chunk)))
    (overlay-put region 'before-string
                 (and (= (overlay-start region) (overlay-end region))
                      (not (+my/merge--resolved-p chunk))
                      (propertize " " 'display
                                  `(left-fringe right-triangle
                                                ,(if (eq (+my/merge-chunk-kind chunk) 'conflict)
                                                     '+my/merge-mark-conflict
                                                   '+my/merge-mark)))))))

(defun +my/merge--render-edited (session)
  "SESSION's changes shown again whose lines in the Result an edit (by hand,
an undo) made done or not done (see EDITED BY HAND, changes.el); the bar too
then."
  (let ((shown nil))
    (seq-doseq (chunk (+my/merge-chunks session))
      (unless (eq (overlay-get (+my/merge-chunk-result chunk) 'face) (+my/merge--face chunk 'result))
        (+my/merge--render-chunk chunk)
        (setq shown t)))
    (when shown
      (+my/merge--render-bar session))))

(defun +my/merge--counts (session)
  "(CHANGES-LEFT . CONFLICTS-LEFT) of SESSION."
  (let ((left 0) (conflicts 0))
    (seq-doseq (chunk (+my/merge-chunks session))
      (unless (+my/merge--resolved-p chunk)
        (cl-incf left)
        (when (eq (+my/merge-chunk-kind chunk) 'conflict)
          (cl-incf conflicts))))
    (cons left conflicts)))

(defun +my/merge--refine (session)
  "Highlight the words each change changed (smerge's): a conflict's sides
against each other, another change against the base."
  (require 'smerge-mode)
  (let ((chunks (+my/merge-chunks session))
        (marker (lambda (ov edge)
                  (with-current-buffer (overlay-buffer ov)
                    (copy-marker (if (eq edge 'start) (overlay-start ov) (overlay-end ov))))))
        (short (lambda (ov)
                 (with-current-buffer (overlay-buffer ov)
                   (<= (count-lines (overlay-start ov) (overlay-end ov)) +my/merge-refine-max-lines)))))
    (when (<= (length chunks) +my/merge-refine-max-changes)
      (seq-doseq (chunk chunks)
        (let ((base-start (with-current-buffer (+my/merge-base session)
                            (copy-marker (overlay-start (+my/merge-chunk-result chunk)))))
              (pairs (if (eq (+my/merge-chunk-kind chunk) 'conflict)
                         (list (cons (+my/merge-chunk-yours chunk) (+my/merge-chunk-theirs chunk)))
                       (mapcar (lambda (side) (cons (+my/merge--overlay chunk side) nil))
                               (seq-filter (lambda (side) (+my/merge--changed-p chunk side))
                                           '(yours theirs))))))
          (pcase-dolist (`(,one . ,two) pairs)
            (let ((one-start (funcall marker one 'start))
                  (one-end (funcall marker one 'end))
                  (two-start (if two (funcall marker two 'start) base-start))
                  (two-end (if two (funcall marker two 'end)
                             (with-current-buffer (+my/merge-base session)
                               (copy-marker (+ base-start (length (+my/merge-chunk-base chunk))))))))
              (when (and (< one-start one-end) (< two-start two-end)
                         (funcall short one) (or (not two) (funcall short two)))
                (ignore-errors
                  (smerge-refine-regions one-start one-end two-start two-end
                                         '((face . +my/merge-refined) (+my/merge-refined . t))))))))))))
