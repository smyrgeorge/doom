;;; $DOOMDIR/config/merge.el -*- lexical-binding: t; -*-
;; Resolving merge conflicts in three panes, like IntelliJ's. Loaded from
;; config.el.

;; ====== VARIABLES ======

;; RESOLVING CONFLICTS
;; e on a conflicted file in Magit (its status: Unmerged) opens it in three
;; panes, under a bar: Yours (your side: the branch you're on in a merge or a
;; cherry-pick, what you're rebasing onto in a rebase), the Result (the file
;; as it'll be saved, starting from the version both sides came from), Theirs
;; (the branch merged, the commit being rebased or cherry-picked, the stash).
;; Each change of a side is highlighted (changed lines blue, added green,
;; removed grey, conflicts red: both sides changed them), with buttons in its
;; pane's margin, by the Result:
;;   >> / <<   put the change in the Result. In a conflict whose other side is
;;             in already, add it after that one (keep both).
;;   x         ignore the change (the Result keeps what it has there).
;; A change is done when each side that changed is in or ignored; it then
;; turns grey. The words that changed are highlighted too (smerge's).
;; A conflict whose sides changed different words gets a ✨ wand in the
;; Result's margin: it merges them, word by word (see THE WAND).
;; The bar, across the top:
;;   Accept Left / Accept Right   Yours / Theirs for every change not done yet
;;   ✨ Apply non-conflicting      every change only one side made (or both
;;                                the same), not done yet
;;   N changes left, M conflicts
;;   Done    save the file, and stage it (git add) if no change is left; with
;;           some left, ask first, and save them as conflict markers, unstaged
;;   Abort   close, the file left as it was
;; The panes line up: each change takes as many rows in each, the shorter
;; padded with grey filler lines (not text: not saved, not copied, the cursor
;; skips them); and they scroll together (the wheel, the trackpad, the keys,
;; smooth scrolling's glides; sideways too).
;; The Result can be edited as any file; u undoes the buttons too (and C-r
;; redoes them). Keys in the panes: ]c / [c next / previous change; SPC m l /
;; SPC m r the change at point from Yours / Theirs, SPC m x ignore it, SPC m w
;; the wand, SPC m L
;; / SPC m R accept left / right, SPC m a apply non-conflicting; C-c C-c (or
;; Cmd+S) done, C-c C-k abort.
;; The three versions are Git's, from its index (stages :1: the base, :2:
;; yours, :3: theirs): merges, rebases, cherry-picks, reverts and stashes
;; alike. Ediff finds the changes (its diff3 parser, comparing the three: it
;; says which side changed each region, or both), without its windows. Binary files, files added on
;; both sides or deleted on one, submodules and links open in Magit's usual
;; Ediff instead (each version isn't a text with a common base).
(defvar +my/merge-refine-max-lines 200
  "Changes longer than this (lines) on a side aren't refined word by word.")

(defvar +my/merge-refine-max-changes 100
  "Files with more changes than this aren't refined word by word.")

(defface +my/merge-changed '((t :inherit diff-changed :extend t))
  "A side's change of lines (blue, see `+my/merge-faces-h').")

(defface +my/merge-added '((t :inherit diff-added :extend t))
  "A side's added lines (green).")

(defface +my/merge-removed '((t :inherit shadow :extend t))
  "Where a side removed lines (grey).")

(defface +my/merge-conflict '((t :inherit diff-removed :extend t))
  "A conflict: both sides changed the lines, differently (red).")

(defface +my/merge-done '((t :inherit shadow))
  "A side's change once done (in the Result, or ignored).")

(defface +my/merge-filler '((t :inherit fringe :extend t))
  "The filler lines that line the panes up (see `+my/merge-faces-h').")

(defface +my/merge-refined '((t :inherit smerge-refined-changed))
  "The words a change changed.")

(defface +my/merge-button '((t :inherit (bold link) :underline nil))
  "The buttons in the margins and the bar.")

(defvar +my/merge-mode-map (make-sparse-keymap)
  "Keys in the three panes (see `+my/merge-mode').")

;; ====== KEY BINDINGS ======

(map! :map +my/merge-mode-map
      "C-c C-c" #'+my/merge-done
      "C-c C-k" #'+my/merge-abort
      "s-s"     #'+my/merge-done      ; the Result visits no file: Done saves it
      [left-margin mouse-1]  #'+my/merge-click
      [right-margin mouse-1] #'+my/merge-click
      [left-margin down-mouse-1]  #'ignore
      [right-margin down-mouse-1] #'ignore
      :nm "]c" #'+my/merge-next
      :nm "[c" #'+my/merge-previous)

(map! :map +my/merge-mode-map
      :localleader
      :desc "Change at point from Yours"  "l" #'+my/merge-take-left
      :desc "Change at point from Theirs" "r" #'+my/merge-take-right
      :desc "Ignore change at point"      "x" #'+my/merge-ignore
      :desc "Merge the words (wand)"      "w" #'+my/merge-wand
      :desc "Accept Left"                 "L" #'+my/merge-accept-left
      :desc "Accept Right"                "R" #'+my/merge-accept-right
      :desc "Apply non-conflicting"       "a" #'+my/merge-apply-non-conflicting
      :desc "Done"                        "d" #'+my/merge-done
      :desc "Abort"                       "q" #'+my/merge-abort)

;; e in Magit, on a conflicted file.
(after! magit-ediff
  (setq magit-ediff-dwim-resolve-function #'+my/merge))

;; ====== CODE ======

(cl-defstruct (+my/merge (:constructor +my/merge--make) (:copier nil))
  "A file being resolved."
  path toplevel coding labels
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
UP).")

(define-minor-mode +my/merge-mode
  "A pane of a merge (see config/merge.el).

\\{+my/merge-mode-map}"
  :keymap +my/merge-mode-map)

;; THE VERSIONS (Git's index)
(defun +my/merge--git (&rest args)
  "Run git with ARGS in the current folder; its output as bytes (unibyte), or
nil if it failed."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary)
          (process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
      (and (zerop (apply #'process-file (or (bound-and-true-p magit-git-executable) "git")
                         nil t nil args))
           (buffer-string)))))

(defun +my/merge--stages (path)
  "PATH's stages in the index: ((STAGE . MODE)...)."
  (let ((out (+my/merge--git "ls-files" "-u" "--" path))
        stages)
    (dolist (line (and out (split-string out "\n" t)))
      (when (string-match "\\`\\([0-7]+\\) [0-9a-f]+ \\([123]\\)\t" line)
        (push (cons (string-to-number (match-string 2 line)) (match-string 1 line)) stages)))
    (nreverse stages)))

(defun +my/merge--blob (stage path)
  "PATH's version STAGE in the index, as bytes."
  (or (+my/merge--git "show" (format ":%d:%s" stage path))
      (error "Git has no version %d of %s" stage path)))

(defun +my/merge--binary-p (bytes)
  "Non-nil if BYTES look binary, as Git decides: a NUL in their first 8000."
  (string-search "\0" (substring bytes 0 (min 8000 (length bytes)))))

(defun +my/merge--why-not (path)
  "Why PATH's conflict can't be resolved in three panes (a string), or nil."
  (let* ((stages (+my/merge--stages path))
         (modes (mapcar #'cdr stages)))
    (cond ((null stages) "Not in conflict")
          ((not (assq 1 stages)) "Added on both sides")
          ((not (assq 2 stages)) "Deleted on your side")
          ((not (assq 3 stages)) "Deleted on their side")
          ((member "160000" modes) "A submodule")
          ((member "120000" modes) "A link")
          ((seq-some (lambda (stage) (+my/merge--binary-p (+my/merge--blob stage path)))
                     '(1 2 3))
           "A binary file"))))

(defun +my/merge--coding (bytes)
  "The coding system to read BYTES (a version) and write the Result with."
  (let ((coding (car (detect-coding-string bytes))))
    (if (memq (coding-system-base coding) '(undecided prefer-utf-8 raw-text))
        (coding-system-change-text-conversion coding 'utf-8)
      coding)))

(defun +my/merge--labels ()
  "What Yours and Theirs are, (YOURS . THEIRS), from the operation going on."
  (let* ((rev (lambda (name) (and (magit-rev-verify name) name)))
         (subject (lambda (rev) (magit-rev-format "%h %s" rev)))
         (branch (or (magit-get-current-branch) (magit-rev-abbrev "HEAD") "HEAD")))
    (cond ((funcall rev "MERGE_HEAD")
           (cons branch (or (magit-rev-name "MERGE_HEAD" "refs/heads/*")
                            (funcall subject "MERGE_HEAD"))))
          ((funcall rev "REBASE_HEAD")
           (cons (format "%s (rebasing onto)" (funcall subject "HEAD"))
                 (format "%s (being rebased)" (funcall subject "REBASE_HEAD"))))
          ((funcall rev "CHERRY_PICK_HEAD")
           (cons branch (format "%s (cherry-picked)" (funcall subject "CHERRY_PICK_HEAD"))))
          ((funcall rev "REVERT_HEAD")
           (cons branch (format "revert of %s" (funcall subject "REVERT_HEAD"))))
          (t (cons branch "the change applied (a stash...)")))))

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
          (with-temp-buffer
            (let ((ediff-buffer-A (+my/merge-yours session))
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
                       :base (+my/merge--text (+my/merge-base session) (aref diff 2) (aref diff 3)))))
          (dolist (ov (list yours theirs result))
            (overlay-put ov '+my/merge-chunk chunk)
            (overlay-put ov 'priority -10))
          chunk))
      (+my/merge--diff3 session)))))

;; A CHANGE'S STATE
(defun +my/merge--overlay (chunk side)
  "CHUNK's overlay in SIDE's pane (yours, theirs, result)."
  (pcase side
    ('yours (+my/merge-chunk-yours chunk))
    ('theirs (+my/merge-chunk-theirs chunk))
    ('result (+my/merge-chunk-result chunk))))

(defun +my/merge--side-text (chunk side)
  "CHUNK's text on SIDE (yours, theirs)."
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
  "Non-nil if SIDE's change in CHUNK is done (in the Result, ignored), or it
made none."
  (or (not (+my/merge--changed-p chunk side)) (+my/merge--state chunk side)))

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
        (move-overlay ov start (+ start (length text)))))
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
                      (+my/merge--result-of chunk yours theirs order))
      (with-current-buffer (overlay-buffer (+my/merge-chunk-result chunk))
        (+my/merge--align +my/merge--session)))))

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
        ((+my/merge--state chunk side) '+my/merge-done)
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
                               'mouse-face 'highlight 'help-echo help)
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
           (let ((apply (+my/merge--button
                         (if (eq side 'yours)
                             (+my/merge--icon "nf-md-chevron_double_right" ">>")
                           (+my/merge--icon "nf-md-chevron_double_left" "<<"))
                         'applied chunk side
                         (if (and (eq (+my/merge-chunk-kind chunk) 'conflict)
                                  (eq (+my/merge--state chunk other) 'applied))
                             (format "Add after %s's (keep both)" (if (eq other 'yours) "Yours" "Theirs"))
                           "Put in the Result")))
                 (ignore (+my/merge--button (+my/merge--icon "nf-cod-close" "x")
                                            'ignored chunk side "Ignore")))
             (if (eq side 'yours) (concat apply " " ignore) (concat ignore " " apply)))))))

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
                     (propertize " " 'display `((margin ,(if (eq side 'yours) 'right-margin 'left-margin))
                                                ,text)))
        (push ov (+my/merge-chunk-buttons chunk)))))
  ;; The wand, in the Result's margin, while it can merge.
  (when (and (+my/merge-chunk-wand chunk) (not (+my/merge--resolved-p chunk)))
    (let* ((region (+my/merge-chunk-result chunk))
           (ov (make-overlay (overlay-start region) (overlay-start region) (overlay-buffer region))))
      (overlay-put ov 'before-string
                   (propertize " " 'display
                               `((margin left-margin)
                                 ,(+my/merge--button (+my/merge--icon "nf-cod-wand" "*")
                                                     'merged chunk 'both
                                                     "Merge the words both sides changed (wand)"))))
      (push ov (+my/merge-chunk-buttons chunk))))
  ;; A change with nothing in the Result: a mark in its fringe.
  (let ((region (+my/merge-chunk-result chunk)))
    (overlay-put region 'before-string
                 (and (= (overlay-start region) (overlay-end region))
                      (not (+my/merge--resolved-p chunk))
                      (propertize " " 'display `(left-fringe right-triangle ,(+my/merge--face chunk 'result)))))))

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

;; LINING UP
;; Each change takes as many rows in each pane: after it, the shorter ones get
;; filler lines (the most of the three, less their own). They're text, so that
;; any row can be scrolled to (a window can't start inside an overlay's
;; string, which can't be scrolled into either): newlines marked
;; `+my/merge-filler', read-only, skipped by the cursor, left out of what's
;; saved or copied. In the Result, they're made again after each command that
;; changed it, in the same step of its undo.
(defvar-local +my/merge--dirty nil
  "Non-nil if the pane changed since its fillers were made.")

(defun +my/merge--filler (n)
  "N filler lines."
  (propertize (make-string n ?\n)
              '+my/merge-filler t 'face '+my/merge-filler 'read-only t
              'cursor-intangible t 'rear-nonsticky t))

(defun +my/merge--height (ov)
  "The lines of OV's region (a last one without its newline counts)."
  (with-current-buffer (overlay-buffer ov)
    (count-lines (overlay-start ov) (overlay-end ov))))

(defun +my/merge--fillers-at (pos)
  "The end of the fillers at POS in the current buffer (POS if none)."
  (if (and (< pos (point-max)) (get-text-property pos '+my/merge-filler))
      (next-single-property-change pos '+my/merge-filler nil (point-max))
    pos))

(defun +my/merge--fill (ov n)
  "N filler lines after OV's region, in its buffer."
  (with-current-buffer (overlay-buffer ov)
    (let* ((pos (overlay-end ov))
           (end (+my/merge--fillers-at pos))
           (have (- end pos)))
      (unless (= have n)
        (let ((inhibit-read-only t)
              (+my/merge--aligning t))
          (save-excursion
            (if (> have n)
                (delete-region (+ pos n) end)
              (goto-char end)
              (insert (+my/merge--filler (- n have))))))))))

(defun +my/merge--align (session)
  "Line SESSION's panes up (see above)."
  (seq-doseq (chunk (+my/merge-chunks session))
    (let* ((sides (list (+my/merge-chunk-yours chunk) (+my/merge-chunk-result chunk)
                        (+my/merge-chunk-theirs chunk)))
           (heights (mapcar #'+my/merge--height sides))
           (most (apply #'max heights)))
      (cl-mapc (lambda (ov height) (+my/merge--fill ov (- most height)))
               sides heights)))
  (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
    (with-current-buffer buffer
      (setq +my/merge--dirty nil))))

(defun +my/merge--changed-h (&rest _)
  "The pane changed: its fillers made again after this command."
  (unless +my/merge--aligning
    (setq +my/merge--dirty t)))

(defun +my/merge--post-command-h ()
  "After a command: the panes lined up again if the Result changed (an edit,
an undo)."
  (when-let* ((session +my/merge--session)
              ((not (+my/merge-finished session)))
              ((buffer-live-p (+my/merge-result session)))
              ((buffer-local-value '+my/merge--dirty (+my/merge-result session))))
    (with-current-buffer (+my/merge-result session)
      (+my/merge--align session))))

(defun +my/merge--clean (start end)
  "The text from START to END of the current buffer, without fillers."
  (let ((pos start)
        (parts nil))
    (while (< pos end)
      (let ((next (min end (next-single-property-change pos '+my/merge-filler nil end))))
        (unless (get-text-property pos '+my/merge-filler)
          (push (buffer-substring-no-properties pos next) parts))
        (setq pos next)))
    (apply #'concat (nreverse parts))))

(defun +my/merge--filter-substring (beg end &optional delete)
  "`filter-buffer-substring-function' of the panes: copies without fillers."
  (prog1 (+my/merge--clean beg end)
    (when delete
      (delete-region beg end))))

;; SCROLLING TOGETHER
;; Lined up, the panes' rows are their lines: the pane scrolled (its first
;; line, the pixels of it scrolled off, its columns scrolled sideways) gives
;; the others theirs, before each redisplay; so whatever scrolled it: keys, the
;; wheel, the trackpad, a glide of config/smooth.el's (its frames are timers,
;; each followed by a redisplay).
(defun +my/merge--view (window)
  "WINDOW's view: (FIRST-LINE VSCROLL HSCROLL)."
  (list (with-current-buffer (window-buffer window)
          (line-number-at-pos (window-start window)))
        (window-vscroll window t)
        (window-hscroll window)))

(defun +my/merge--sync-h (&optional window)
  "Before a redisplay: a pane that scrolled scrolls the others (see above)."
  (dolist (window (if window (list window) (window-list nil 'nomini)))
    (when-let* ((session (and (window-live-p window)
                              (buffer-local-value '+my/merge--session (window-buffer window))))
                ((not (+my/merge-finished session)))
                ((not (eq (window-buffer window) (+my/merge-bar session))))
                (view (+my/merge--view window))
                ((not (equal view (window-parameter window '+my/merge-view)))))
      (pcase-let ((`(,line ,vscroll ,hscroll) view))
        (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session)
                              (+my/merge-theirs session)))
          (dolist (other (get-buffer-window-list buffer 'nomini))
            (unless (eq other window)
              (set-window-start other (with-current-buffer buffer
                                        (save-excursion
                                          (goto-char (point-min))
                                          (forward-line (1- line))
                                          (point))))
              ;; Kept through redisplay (as ultra-scroll does), and point off
              ;; a first line scrolled partly off: redisplay would scroll
              ;; back to show it.
              (set-window-vscroll other vscroll t t)
              (when (> vscroll 0)
                (let ((second (with-current-buffer buffer
                                (save-excursion
                                  (goto-char (window-start other))
                                  (forward-line 1)
                                  (point)))))
                  (when (< (window-point other) second)
                    (set-window-point other second))))
              (set-window-hscroll other hscroll)
              (set-window-parameter other '+my/merge-view (+my/merge--view other)))))
        (set-window-parameter window '+my/merge-view view)))))

(add-hook 'pre-redisplay-functions #'+my/merge--sync-h)

;; THE BAR
(defun +my/merge--bar-button (label command help)
  (insert-text-button label 'action (lambda (_) (+my/merge--from-bar command))
                      'face '+my/merge-button 'follow-link t 'help-echo help))

(defun +my/merge--from-bar (command)
  "A button of the bar: COMMAND, from the Result's pane."
  (let ((session +my/merge--session))
    (when-let* ((window (get-buffer-window (+my/merge-result session))))
      (select-window window))
    (call-interactively command)))

(defun +my/merge--render-bar (session)
  "Show SESSION's bar: its buttons and what's left."
  (when-let* ((bar (and session (+my/merge-bar session)))
              ((buffer-live-p bar)))
    (with-current-buffer bar
      (let ((inhibit-read-only t)
            (counts (+my/merge--counts session)))
        (erase-buffer)
        (insert " ")
        (+my/merge--bar-button "Accept Left" #'+my/merge-accept-left
                               "Yours for every change not done yet")
        (insert "  ")
        (+my/merge--bar-button "Accept Right" #'+my/merge-accept-right
                               "Theirs for every change not done yet")
        (insert "  ")
        (+my/merge--bar-button "✨ Apply non-conflicting" #'+my/merge-apply-non-conflicting
                               "Every change only one side made, not done yet")
        (insert "   "
                (propertize
                 (if (zerop (car counts))
                     "All changes done"
                   (format "%d change%s left, %d conflict%s"
                           (car counts) (if (= (car counts) 1) "" "s")
                           (cdr counts) (if (= (cdr counts) 1) "" "s")))
                 'face (if (zerop (car counts)) 'success 'warning))
                "   ")
        (+my/merge--bar-button "Done" #'+my/merge-done
                               "Save the file, and stage it if no change is left")
        (insert "  ")
        (+my/merge--bar-button "Abort" #'+my/merge-abort "Close, the file left as it was")
        (goto-char (point-min))))))

(define-derived-mode +my/merge-bar-mode special-mode "Merge"
  "The bar above a merge's panes (see config/merge.el)."
  (setq-local mode-line-format nil
              header-line-format nil
              cursor-type nil
              window-size-fixed 'height))

;; OPENING
(defun +my/merge--pane (name text mode-file &optional editable)
  "A pane's buffer NAME with TEXT, in the mode MODE-FILE's name gives (its
hooks not run: no language server, linter...), read-only unless EDITABLE."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer
      (insert text)
      (goto-char (point-min))
      (let ((buffer-file-name (expand-file-name mode-file)))
        (delay-mode-hooks
          (ignore-errors (set-auto-mode))))
      (font-lock-mode 1)
      (set-buffer-modified-p nil)
      (setq buffer-read-only (not editable))
      ;; Only the Result's edits are undone (the others' are fillers).
      (unless editable
        (buffer-disable-undo))
      (when (fboundp '+my/tabs-off-h)
        (+my/tabs-off-h)))
    buffer))

(defun +my/merge--layout (session)
  "SESSION's panes: the bar across the top, Yours, the Result (selected),
Theirs."
  (let ((window-min-height 1)
        (window-safe-min-height 1)
        (window-min-width 10))
    (when (window-parameter nil 'window-side)
      (select-window (window-main-window)))
    (delete-other-windows)
    (let* ((left (selected-window))
           (bar (split-window left -2 'above))
           (middle (split-window left (- (* 2 (/ (window-total-width left) 3))) 'right))
           (right (split-window middle (- (/ (window-total-width middle) 2)) 'right)))
      (set-window-buffer bar (+my/merge-bar session))
      (set-window-dedicated-p bar t)
      (set-window-parameter bar 'no-other-window t)
      (set-window-parameter bar 'no-delete-other-windows t)
      (fit-window-to-buffer bar 1 1)
      (window-preserve-size bar nil t)
      (pcase-dolist (`(,window ,buffer ,margin) `((,left ,(+my/merge-yours session) right)
                                                   (,middle ,(+my/merge-result session) nil)
                                                   (,right ,(+my/merge-theirs session) left)))
        (set-window-buffer window buffer)
        (set-window-margins window (pcase margin ('left 5) ('nil 2)) (and (eq margin 'right) 5))
        (set-window-start window (point-min))
        (set-window-prev-buffers window nil))
      (select-window middle)
      (dolist (window (list left middle right))
        (set-window-parameter window '+my/merge-view (+my/merge--view window)))
      (list left middle right bar))))

(defun +my/merge--start (path)
  "Resolve PATH's conflict (relative to the repository's top, the current
folder) in three panes."
  (let* ((bytes (mapcar (lambda (stage) (+my/merge--blob stage path)) '(1 2 3)))
         (coding (+my/merge--coding (nth 1 bytes)))
         (texts (mapcar (lambda (b) (decode-coding-string b coding)) bytes))
         (labels (+my/merge--labels))
         (session (+my/merge--make :path path :toplevel default-directory :coding coding
                                   :labels labels
                                   :winconf (current-window-configuration))))
    (setf (+my/merge-base session) (+my/merge--pane (format " *merge base: %s*" path) (nth 0 texts) path)
          (+my/merge-yours session) (+my/merge--pane (format "Yours: %s" path) (nth 1 texts) path)
          (+my/merge-theirs session) (+my/merge--pane (format "Theirs: %s" path) (nth 2 texts) path)
          (+my/merge-result session) (+my/merge--pane (format "Result: %s" path) (nth 0 texts) path t)
          (+my/merge-bar session) (generate-new-buffer (format " *merge: %s*" path)))
    (setf (+my/merge-chunks session) (+my/merge--chunks session))
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-theirs session)
                          (+my/merge-result session) (+my/merge-base session)
                          (+my/merge-bar session)))
      (with-current-buffer buffer
        (setq +my/merge--session session)
        (setq default-directory (+my/merge-toplevel session))
        (add-hook 'kill-buffer-hook #'+my/merge--killed-h nil t)))
    (with-current-buffer (+my/merge-bar session)
      (+my/merge-bar-mode)
      (setq +my/merge--session session)
      (add-hook 'kill-buffer-hook #'+my/merge--killed-h nil t))
    (pcase-dolist (`(,buffer ,title) `((,(+my/merge-yours session) ,(concat "Yours: " (car labels)))
                                       (,(+my/merge-result session) ,(concat "Result: " path))
                                       (,(+my/merge-theirs session) ,(concat "Theirs: " (cdr labels)))))
      (with-current-buffer buffer
        ;; First: turned off, it puts back the buffer's `truncate-lines'.
        (when (bound-and-true-p visual-line-mode)
          (visual-line-mode -1))
        (setq-local header-line-format (concat " " (propertize title 'face 'bold))
                    ;; A row a line: lined up (see LINING UP).
                    truncate-lines t
                    filter-buffer-substring-function #'+my/merge--filter-substring)
        (cursor-intangible-mode 1)
        (add-hook 'after-change-functions #'+my/merge--changed-h nil t)
        (add-hook 'post-command-hook #'+my/merge--post-command-h nil t)
        (+my/merge-mode 1)))
    (with-current-buffer (+my/merge-result session)
      (setq buffer-undo-list nil))
    (+my/merge--refine session)
    (seq-doseq (chunk (+my/merge-chunks session))
      (setf (+my/merge-chunk-wand chunk) (+my/merge--wand-of chunk))
      (+my/merge--render-chunk chunk))
    (with-current-buffer (+my/merge-result session)
      (let ((buffer-undo-list t))
        (+my/merge--align session)))
    (+my/merge--render-bar session)
    (+my/merge--layout session)
    ;; At the first change.
    (when-let* ((first (seq-first (+my/merge-chunks session))))
      (+my/merge--goto first))
    (message "%s: %s" path (with-current-buffer (+my/merge-bar session)
                              (string-trim (buffer-string))))
    session))

(defun +my/merge (file)
  "Resolve FILE's conflicts in three panes: Yours, the Result, Theirs (see
config/merge.el); Magit's Ediff for what they can't show."
  (interactive (progn (require 'magit) (list (magit-read-unmerged-file))))
  (require 'magit)
  (magit-with-toplevel
    (let* ((path (file-relative-name (expand-file-name file) default-directory))
           (why (+my/merge--why-not path)))
      (cond ((not why) (+my/merge--start path))
            ((equal why "Not in conflict") (user-error "%s has no conflict" path))
            (t (message "%s: %s, so Ediff" path why)
               (magit-ediff-resolve-rest path))))))

;; CLOSING
(defun +my/merge--session ()
  (or +my/merge--session (user-error "Not in a merge")))

(defun +my/merge--finish (session)
  "Close SESSION: its panes, the windows as they were."
  (unless (+my/merge-finished session)
    (setf (+my/merge-finished session) t)
    (ignore-errors (set-window-configuration (+my/merge-winconf session)))
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-theirs session)
                          (+my/merge-result session) (+my/merge-base session)
                          (+my/merge-bar session)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))
    (when (fboundp 'magit-refresh-all)
      (let ((default-directory (+my/merge-toplevel session)))
        (ignore-errors (magit-refresh-all))))))

(defun +my/merge--killed-h ()
  "A pane closed (Cmd+W, say): the merge with it, aborted."
  (when (and +my/merge--session (not (+my/merge-finished +my/merge--session)))
    (let ((session +my/merge--session))
      (run-at-time 0 nil #'+my/merge--finish session))))

(defun +my/merge--markers (session)
  "SESSION's Result, the changes not done as conflict markers (Git's)."
  (with-current-buffer (+my/merge-result session)
    (let ((labels (+my/merge-labels session))
          (line (lambda (text) (if (or (string-empty-p text) (string-suffix-p "\n" text))
                                   text (concat text "\n"))))
          (pos (point-min))
          (parts nil))
      (seq-doseq (chunk (+my/merge-chunks session))
        (unless (+my/merge--resolved-p chunk)
          (let ((ov (+my/merge-chunk-result chunk)))
            (push (+my/merge--clean pos (overlay-start ov)) parts)
            (push (concat "<<<<<<< " (car labels) "\n"
                          (funcall line (+my/merge--side-text chunk 'yours))
                          "=======\n"
                          (funcall line (+my/merge--side-text chunk 'theirs))
                          ">>>>>>> " (cdr labels) "\n")
                  parts)
            (setq pos (overlay-end ov)))))
      (push (+my/merge--clean pos (point-max)) parts)
      (apply #'concat (nreverse parts)))))

(defun +my/merge--result-text (session)
  "SESSION's Result, as it'll be saved (without fillers)."
  (with-current-buffer (+my/merge-result session)
    (+my/merge--clean (point-min) (point-max))))

(defun +my/merge--write (session text)
  "Write TEXT to SESSION's file, as is (no save hooks: formatting...); a
buffer visiting it shows it then (asked first if it has changes not saved)."
  (let* ((file (expand-file-name (+my/merge-path session) (+my/merge-toplevel session)))
         (buffer (find-buffer-visiting file)))
    (when (and buffer (buffer-modified-p buffer)
               (not (yes-or-no-p (format "%s has changes not saved: replace them? "
                                         (buffer-name buffer)))))
      (user-error "Not done"))
    (let ((coding-system-for-write (+my/merge-coding session)))
      (write-region text nil file nil 'silent))
    (when buffer
      (with-current-buffer buffer
        (revert-buffer t t t)))))

(defun +my/merge-done ()
  "Done: save the file, and stage it if no change is left; with some left,
ask first, and save them as conflict markers, not staged."
  (interactive)
  (let* ((session (+my/merge--session))
         (left (car (+my/merge--counts session))))
    (cond ((zerop left)
           (+my/merge--write session (+my/merge--result-text session))
           (let ((default-directory (+my/merge-toplevel session)))
             (+my/merge--git "add" "--" (+my/merge-path session)))
           (+my/merge--finish session)
           (message "%s resolved and staged" (+my/merge-path session)))
          ((y-or-n-p (format "%d change%s not done: save %s with conflict markers there, not staged? "
                             left (if (= left 1) " is" "s are") (+my/merge-path session)))
           (+my/merge--write session (+my/merge--markers session))
           (+my/merge--finish session)
           (message "%s saved with %d conflict%s left, not staged"
                    (+my/merge-path session) left (if (= left 1) "" "s"))))))

(defun +my/merge-abort ()
  "Abort: close, the file left as it was."
  (interactive)
  (let ((session (+my/merge--session)))
    (+my/merge--finish session)
    (message "Merge of %s aborted: the file is as it was" (+my/merge-path session))))

;; COMMANDS
(defun +my/merge-click (event)
  "A click in a pane's margin: the button there."
  (interactive "e")
  (let* ((posn (event-start event))
         (string (posn-string posn))
         (action (and (car string) (cdr string)
                      (get-text-property (cdr string) '+my/merge-action (car string)))))
    (when (window-live-p (posn-window posn))
      (select-window (posn-window posn)))
    (when action
      (apply #'+my/merge--decide action))))

(defun +my/merge--chunk-at (&optional pos)
  "The change at POS (point) in the current pane, or the next one on its line."
  (let ((pos (or pos (point))))
    (or (seq-some (lambda (ov) (overlay-get ov '+my/merge-chunk))
                  (overlays-at pos))
        (seq-some (lambda (ov) (overlay-get ov '+my/merge-chunk))
                  (overlays-in (line-beginning-position) (min (point-max) (1+ (line-end-position))))))))

(defun +my/merge--chunk-here ()
  (or (+my/merge--chunk-at) (user-error "No change here")))

(defun +my/merge-take-left ()
  "SPC m l: the change at point from Yours (after Theirs' if in: keep both)."
  (interactive)
  (+my/merge--decide (+my/merge--chunk-here) 'yours 'applied))

(defun +my/merge-take-right ()
  "SPC m r: the change at point from Theirs (after Yours' if in: keep both)."
  (interactive)
  (+my/merge--decide (+my/merge--chunk-here) 'theirs 'applied))

(defun +my/merge-ignore ()
  "SPC m x: ignore the change at point (both sides' not in yet)."
  (interactive)
  (let ((chunk (+my/merge--chunk-here)))
    (dolist (side '(yours theirs))
      (unless (+my/merge--state chunk side)
        (+my/merge--decide chunk side 'ignored)))))

(defun +my/merge-wand ()
  "SPC m w: the wand on the conflict at point: its sides' words merged."
  (interactive)
  (let ((chunk (+my/merge--chunk-here)))
    (unless (+my/merge-chunk-wand chunk)
      (user-error "No wand here: the sides changed the same words, or it's no conflict"))
    (+my/merge--merge-words-in chunk)))

(defun +my/merge--accept (side)
  "SIDE for every change not done yet (the other side's ignored)."
  (seq-doseq (chunk (+my/merge-chunks (+my/merge--session)))
    (unless (+my/merge--resolved-p chunk)
      (if (+my/merge--changed-p chunk side)
          (progn (unless (+my/merge--state chunk side)
                   (+my/merge--decide chunk side 'applied))
                 (unless (+my/merge--handled-p chunk (+my/merge--other side))
                   (+my/merge--decide chunk (+my/merge--other side) 'ignored)))
        (+my/merge--decide chunk (+my/merge--other side) 'ignored)))))

(defun +my/merge-accept-left ()
  "Accept Left: Yours for every change not done yet."
  (interactive)
  (+my/merge--accept 'yours))

(defun +my/merge-accept-right ()
  "Accept Right: Theirs for every change not done yet."
  (interactive)
  (+my/merge--accept 'theirs))

(defun +my/merge-apply-non-conflicting ()
  "✨ Apply non-conflicting: every change only one side made (or both the
same), not done yet."
  (interactive)
  (let ((n 0))
    (seq-doseq (chunk (+my/merge-chunks (+my/merge--session)))
      (unless (or (eq (+my/merge-chunk-kind chunk) 'conflict) (+my/merge--resolved-p chunk))
        (cl-incf n)
        (+my/merge--decide chunk (if (+my/merge--changed-p chunk 'yours) 'yours 'theirs) 'applied)))
    (message "%d change%s applied" n (if (= n 1) "" "s"))))

(defun +my/merge--goto (chunk)
  "Point at CHUNK in each pane."
  (dolist (side '(yours result theirs))
    (let ((ov (+my/merge--overlay chunk side)))
      (with-current-buffer (overlay-buffer ov)
        (goto-char (overlay-start ov))
        (when-let* ((window (get-buffer-window (current-buffer))))
          (set-window-point window (point))
          (unless (pos-visible-in-window-p (point) window)
            (with-selected-window window (recenter 3))))))))

(defun +my/merge--move (forward)
  (let* ((session (+my/merge--session))
         (side (cond ((eq (current-buffer) (+my/merge-yours session)) 'yours)
                     ((eq (current-buffer) (+my/merge-theirs session)) 'theirs)
                     (t 'result)))
         (chunks (append (+my/merge-chunks session) nil))
         (target (if forward
                     (seq-find (lambda (c) (> (overlay-start (+my/merge--overlay c side)) (line-end-position)))
                               chunks)
                   (seq-find (lambda (c) (< (overlay-start (+my/merge--overlay c side)) (line-beginning-position)))
                             (reverse chunks)))))
    (if target
        (+my/merge--goto target)
      (message "No %s change" (if forward "next" "previous")))))

(defun +my/merge-next ()
  "]c: the next change."
  (interactive)
  (+my/merge--move t))

(defun +my/merge-previous ()
  "[c: the previous change."
  (interactive)
  (+my/merge--move nil))

;; THEME
(defun +my/merge-faces-h ()
  "The changes tinted with the theme's colours, like IntelliJ's."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (face-background 'default nil t)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (pcase-dolist (`(,face ,colour ,amount) '((+my/merge-changed blue 0.25)
                                                   (+my/merge-added green 0.25)
                                                   (+my/merge-removed base5 0.35)
                                                   (+my/merge-conflict red 0.25)
                                                   (+my/merge-filler base5 0.12)))
          (when-let* ((tint (doom-color colour))
                      ((stringp tint)))
            (set-face-attribute face nil :inherit nil :extend t
                                :background (doom-blend tint bg amount))))))))

(+my/merge-faces-h)
(add-hook 'doom-load-theme-hook #'+my/merge-faces-h)
