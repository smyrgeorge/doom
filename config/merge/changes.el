;;; $DOOMDIR/config/merge/changes.el -*- lexical-binding: t; -*-
;; The changes (Ediff's), their state, the wand. Loaded from config/merge.el.

;; THE CHANGES (Ediff's)
(defun +my/merge--diff3 (session)
  "SESSION's changes, from Ediff's diff3 parser, as a three-way comparison of
Yours, the base and Theirs: its vectors (see `ediff-extract-diffs3': positions
in each, and which differs from the other two: A Yours, B the base (both sides
made the same change), C Theirs, nil all (a conflict)). Not as a merge: that
leaves out the changes both sides made the same, which a Result starting
from the base needs."
  (require 'ediff)
  (require 'ediff-diff)
  (let ((files (mapcar (lambda (buffer)
                         (let ((file (make-temp-file "merge-"))
                               (coding-system-for-write 'utf-8-unix))
                           (with-current-buffer buffer
                             (write-region nil nil file nil 'silent)
                             ;; macOS's diff3 (BSD's) glues a last line without
                             ;; its newline to its next line of output, which
                             ;; Ediff can't read: one added (a change of the
                             ;; final newline alone isn't seen).
                             (unless (or (= (point-min) (point-max))
                                         (eq (char-before (point-max)) ?\n))
                               (write-region "\n" nil file t 'silent)))
                           file))
                       (list (+my/merge-yours session) (+my/merge-base session)
                             (+my/merge-theirs session))))
        (output (generate-new-buffer " *merge-diff3*")))
    (unwind-protect
        (progn
          ;; Yours, the base, Theirs: Ediff's A, B, C.
          (unless (<= (with-current-buffer output
                        (apply #'call-process ediff-diff3-program nil t nil files))
                      1)
            (error "diff3 failed: %s" (with-current-buffer output (buffer-string))))
          ;; `dlet': Ediff's own variables (its buffers) whatever the compiler
          ;; knew; compiled before Ediff loaded (config/compile.el), a `let'
          ;; bound locals Ediff never saw, the first time (Ediff loads above).
          (with-temp-buffer
            (dlet ((ediff-buffer-A (+my/merge-yours session))
                   (ediff-buffer-B (+my/merge-base session))
                   (ediff-buffer-C (+my/merge-theirs session))
                   (ediff-ancestor-buffer nil))
              (cdr (ediff-extract-diffs3 output nil t)))))
      (mapc #'delete-file files)
      (kill-buffer output))))

(defun +my/merge--text (buffer begin end)
  (with-current-buffer buffer
    (buffer-substring-no-properties begin end)))

(defun +my/merge--chunks (session)
  "SESSION's changes, as `+my/merge-chunk's (see `+my/merge--diff3')."
  (let ((index -1))
    (vconcat
     (mapcar
      (lambda (diff)
        (let* ((yours (make-overlay (aref diff 0) (aref diff 1) (+my/merge-yours session)))
               (result (make-overlay (aref diff 2) (aref diff 3) (+my/merge-result session)))
               (theirs (make-overlay (aref diff 4) (aref diff 5) (+my/merge-theirs session)))
               (kind (pcase (aref diff 8)
                       ('A 'yours)
                       ('B 'same)
                       ('C 'theirs)
                       (_ 'conflict)))
               (chunk (+my/merge-chunk--make
                       :index (cl-incf index) :kind kind
                       :yours yours :theirs theirs :result result
                       :start (set-marker (make-marker) (aref diff 2) (+my/merge-result session))
                       :end (set-marker (make-marker) (aref diff 3) (+my/merge-result session))
                       :base (+my/merge--text (+my/merge-base session) (aref diff 2) (aref diff 3)))))
          (dolist (ov (list yours theirs result))
            (overlay-put ov '+my/merge-chunk chunk)
            (overlay-put ov 'priority -10))
          chunk))
      (+my/merge--diff3 session)))))

;; THE RESULT'S REGIONS
;; A change's region in the Result is an overlay (its colour, the change at
;; point) between two markers. An edit moves both alike, but undo puts back
;; only markers: an edit undone left the overlay empty, the lines it had
;; after it. So after a command that changed the Result, and before a button
;; changes a region, its overlay goes back between its markers.
(defun +my/merge--sync (chunk)
  "CHUNK's overlay in the Result between its markers (see above)."
  (let ((ov (+my/merge-chunk-result chunk)))
    (when (overlay-buffer ov)
      (move-overlay ov (+my/merge-chunk-start chunk) (+my/merge-chunk-end chunk)))))

;; A CHANGE'S STATE
(defun +my/merge--overlay (chunk side)
  "CHUNK's overlay in SIDE's pane (yours, theirs, result)."
  (pcase side
    ('yours (+my/merge-chunk-yours chunk))
    ('theirs (+my/merge-chunk-theirs chunk))
    ('result (+my/merge-chunk-result chunk))))

(defun +my/merge--side-text (chunk side)
  "CHUNK's text on SIDE (yours, theirs; result: the Result's there now)."
  (let ((ov (+my/merge--overlay chunk side)))
    (+my/merge--text (overlay-buffer ov) (overlay-start ov) (overlay-end ov))))

(defun +my/merge--state (chunk side)
  (if (eq side 'yours) (+my/merge-chunk-yours-state chunk) (+my/merge-chunk-theirs-state chunk)))

(defun +my/merge--other (side)
  (if (eq side 'yours) 'theirs 'yours))

(defun +my/merge--changed-p (chunk side)
  "Non-nil if SIDE (yours, theirs) changed CHUNK's region."
  (pcase (+my/merge-chunk-kind chunk)
    ((or 'conflict 'same) t)
    (kind (eq kind side))))

(defun +my/merge--handled-p (chunk side)
  "Non-nil if SIDE's change in CHUNK is done (in the Result, ignored, its
lines there edited by hand), or it made none."
  (or (not (+my/merge--changed-p chunk side)) (+my/merge--state chunk side)
      (+my/merge--edited-p chunk)))

(defun +my/merge--resolved-p (chunk)
  (and (+my/merge--handled-p chunk 'yours) (+my/merge--handled-p chunk 'theirs)))

(defun +my/merge--result-of (chunk yours-state theirs-state order)
  "CHUNK's text in the Result with those states: the sides applied, in ORDER
(keep both: one after the other), else the base."
  (let ((applied (seq-filter (lambda (side)
                               (eq (if (eq side 'yours) yours-state theirs-state) 'applied))
                             order)))
    (cond ((and (eq yours-state 'merged) (eq theirs-state 'merged)) (+my/merge-chunk-wand chunk))
          ((null applied) (+my/merge-chunk-base chunk))
          ((eq (+my/merge-chunk-kind chunk) 'same) (+my/merge--side-text chunk 'yours))
          (t (mapconcat (lambda (side)
                          (let ((text (+my/merge--side-text chunk side)))
                            ;; A last line without its newline, before another.
                            (if (and (not (eq side (car (last applied))))
                                     (not (string-empty-p text))
                                     (not (string-suffix-p "\n" text)))
                                (concat text "\n")
                              text)))
                        applied "")))))

(defun +my/merge--put (chunk yours-state theirs-state order text)
  "Make CHUNK's states YOURS-STATE, THEIRS-STATE and ORDER, and its Result
TEXT: one step of the Result's undo, which undoes (and redoes) them all."
  (let ((ov (+my/merge-chunk-result chunk)))
    (+my/merge--sync chunk)
    (with-current-buffer (overlay-buffer ov)
      (let ((start (overlay-start ov))
            (old (buffer-substring-no-properties (overlay-start ov) (overlay-end ov))))
        (unless (eq buffer-undo-list t)
          (push (list 'apply #'+my/merge--put chunk
                      (+my/merge-chunk-yours-state chunk) (+my/merge-chunk-theirs-state chunk)
                      (+my/merge-chunk-order chunk) old)
                buffer-undo-list))
        (unless (equal old text)
          (setq +my/merge--dirty t)
          (let ((buffer-undo-list t)
                (inhibit-read-only t)
                (+my/merge--aligning t))
            (save-excursion
              (goto-char start)
              (insert text)
              (delete-region (point) (+ (point) (length old))))))
        (move-overlay ov start (+ start (length text)))
        (set-marker (+my/merge-chunk-start chunk) start)
        (set-marker (+my/merge-chunk-end chunk) (+ start (length text)))))
    (setf (+my/merge-chunk-yours-state chunk) yours-state
          (+my/merge-chunk-theirs-state chunk) theirs-state
          (+my/merge-chunk-order chunk) order)
    (+my/merge--render-chunk chunk)
    (+my/merge--render-bar (buffer-local-value '+my/merge--session (overlay-buffer ov)))))

(defun +my/merge--decide (chunk side decision)
  "SIDE's change in CHUNK (yours, theirs): DECISION applied or ignored. SIDE
both and DECISION merged: the wand (see THE WAND)."
  (if (eq decision 'merged)
      (+my/merge--merge-words-in chunk)
    (+my/merge--decide-side chunk side decision)))

(defun +my/merge--decide-side (chunk side decision)
  (when (and (+my/merge--changed-p chunk side)
             (not (eq (+my/merge--state chunk side) decision)))
    (with-current-buffer (overlay-buffer (+my/merge-chunk-result chunk))
      (undo-boundary))
    (let* ((same (eq (+my/merge-chunk-kind chunk) 'same))
           (yours (if (or (eq side 'yours) same) decision (+my/merge-chunk-yours-state chunk)))
           (theirs (if (or (eq side 'theirs) same) decision (+my/merge-chunk-theirs-state chunk)))
           (order (append (remq side (+my/merge-chunk-order chunk))
                          (and (eq decision 'applied) (list side)))))
      (+my/merge--put chunk yours theirs order
                      ;; Ignored: the Result keeps what it has there, edited
                      ;; by hand (see EDITED BY HAND).
                      (if (and (eq decision 'ignored) (+my/merge--edited-p chunk))
                          (+my/merge--side-text chunk 'result)
                        (+my/merge--result-of chunk yours theirs order)))
      (with-current-buffer (overlay-buffer (+my/merge-chunk-result chunk))
        (+my/merge--align +my/merge--session)))))

;; EDITED BY HAND
;; The Result is a buffer to edit: a change's lines there edited by hand (not
;; what its buttons put there) are what's wanted, the change done. x keeps
;; them (ignoring the sides not in), Done saves them, Accept Left / Right and
;; Apply non-conflicting leave them; u undoes the edit, the change not done
;; again.
(defun +my/merge--edited-p (chunk)
  "Non-nil if CHUNK's text in the Result was edited by hand (see above)."
  (and (overlay-buffer (+my/merge-chunk-result chunk))
       (not (equal (+my/merge--side-text chunk 'result)
                   (+my/merge--result-of chunk (+my/merge-chunk-yours-state chunk)
                                         (+my/merge-chunk-theirs-state chunk)
                                         (+my/merge-chunk-order chunk))))))

;; THE WAND
;; A conflict's sides may have changed different words of the same lines
;; (Git's merges are by lines). Each version (the base, Yours, Theirs) split
;; into words, runs of spaces, newlines and other characters, one a line (a
;; newline written \n), and merged by git merge-file: no conflict there, the
;; words joined again are the conflict merged.
(defun +my/merge--words (text)
  "TEXT as git merge-file can merge it by words: a token a line (see
above)."
  (let ((pos 0) (lines nil))
    (while (string-match "[[:alnum:]_]+\\|[ \t]+\\|\n\\|." text pos)
      (let ((token (match-string 0 text)))
        (push (if (equal token "\n") "\\n" token) lines)
        (setq pos (match-end 0))))
    (mapconcat (lambda (line) (concat line "\n")) (nreverse lines) "")))

(defun +my/merge--unwords (lines)
  "LINES (from `+my/merge--words') as the text again."
  (mapconcat (lambda (line) (if (equal line "\\n") "\n" line))
             (split-string lines "\n" t) ""))

(defun +my/merge--merge-words (base yours theirs)
  "YOURS and THEIRS (texts changed from BASE) merged word by word, or nil if
the same words changed (see above)."
  (let ((files (mapcar (lambda (text)
                         (let ((file (make-temp-file "merge-words-"))
                               (coding-system-for-write 'utf-8-unix))
                           (write-region (+my/merge--words text) nil file nil 'silent)
                           file))
                       (list yours base theirs))))
    (unwind-protect
        (when-let* ((out (apply #'+my/merge--git "merge-file" "-p" "--quiet" files)))
          (+my/merge--unwords (decode-coding-string out 'utf-8)))
      (mapc #'delete-file files))))

(defun +my/merge--wand-of (chunk)
  "CHUNK's conflict merged word by word, or nil."
  (when (eq (+my/merge-chunk-kind chunk) 'conflict)
    (let ((merged (+my/merge--merge-words (+my/merge-chunk-base chunk)
                                          (+my/merge--side-text chunk 'yours)
                                          (+my/merge--side-text chunk 'theirs))))
      (and merged
           (not (equal merged (+my/merge--side-text chunk 'yours)))
           (not (equal merged (+my/merge--side-text chunk 'theirs)))
           merged))))

(defun +my/merge--merge-words-in (chunk)
  "The wand on CHUNK: its sides' words merged, in the Result (done)."
  (when-let* ((text (+my/merge-chunk-wand chunk)))
    (with-current-buffer (overlay-buffer (+my/merge-chunk-result chunk))
      (undo-boundary)
      (+my/merge--put chunk 'merged 'merged nil text)
      (+my/merge--align +my/merge--session))))
