;;; $DOOMDIR/config/agent-ui/elements/diff.el -*- lexical-binding: t; -*-
;; Agent UI's diff: changes, as a unified diff gives them. Loaded from
;; config/agent-ui/elements.el.
;;
;; By file (its lines added and removed counted) and hunk, each line with
;; its line number in the new file; added lines green, removed red (in the
;; GUI, on a tint as wide as the pane). RET on a line opens its file there,
;; relative to DIR (the agent's directory). From the diff's text, or a
;; source's: {"poll": "git diff", "every": 5, "into": "diff"}.
;;
;;   ▾ src/parser.c  +2 −1
;;     @@ -40,4 +40,5 @@ parse_expr
;;      40   int depth = 0;
;;         − return NULL;
;;      41 + return parse_term(p);

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-diff--unquote (string)
  "STRING's start, a name git quoted (core.quotePath: \"b/\\317\\203.md\",
its octal escapes UTF-8 bytes; \\\" a quote): (NAME . REST), REST what's
after it; nil if it isn't quoted."
  (when (string-prefix-p "\"" string)
    (let ((i 1) (n (length string)) (bytes nil))
      (while (and (< i n) (not (eq (aref string i) ?\")))
        (let ((c (aref string i)))
          (if (and (eq c ?\\) (< (1+ i) n))
              (let ((d (aref string (1+ i))))
                (if (<= ?0 d ?7)
                    ;; Up to 3 octal digits: a byte.
                    (let ((j (1+ i)) (byte 0))
                      (while (and (< j (min n (+ i 4))) (<= ?0 (aref string j) ?7))
                        (setq byte (+ (* byte 8) (- (aref string j) ?0)) j (1+ j)))
                      (push byte bytes)
                      (setq i j))
                  (push (pcase d (?n ?\n) (?t ?\t) (?a 7) (?b 8) (?f 12) (?r 13) (?v 11) (_ d)) bytes)
                  (cl-incf i 2)))
            (setq bytes (append (nreverse (append (encode-coding-string (string c) 'utf-8) nil)) bytes))
            (cl-incf i))))
      (cons (decode-coding-string (apply #'unibyte-string (nreverse bytes)) 'utf-8)
            (substring string (min n (1+ i)))))))

(defun agent-ui-diff--name (string prefix)
  "A --- or +++ line's STRING as a name: unquoted (git's quoted ones), its
date (diff -u's, after a tab) and PREFIX (a/ or b/) left out."
  (let ((name (or (car (agent-ui-diff--unquote string)) (car (split-string string "\t")))))
    (if (string-prefix-p prefix name) (substring name (length prefix)) name)))

(defun agent-ui-diff--git-name (rest)
  "diff --git's REST (its names): the new one, unquoted, without its b/.
Unquoted, a/X b/X split where both halves match (at the first \" b/\", a
name with one in it was misread); a rename's, by its rename to line."
  (let* ((n (length rest))
         (k (/ (- n 5) 2)))
    (cond
     ((agent-ui-diff--unquote rest)
      (let ((second (string-trim-left (cdr (agent-ui-diff--unquote rest)))))
        (agent-ui-diff--name second "b/")))
     ((string-match " \\(\"b/.*\"\\)\\'" rest) (agent-ui-diff--name (match-string 1 rest) "b/"))
     ((and (string-prefix-p "a/" rest) (>= k 0) (= n (+ 5 (* 2 k)))
           (equal (substring rest (+ 2 k) (+ 5 k)) " b/")
           (equal (substring rest 2 (+ 2 k)) (substring rest (+ 5 k))))
      (substring rest (+ 5 k)))
     ((string-match " b/\\(.*\\)\\'" rest) (match-string 1 rest))
     (t ""))))

(defun agent-ui-diff--parse (text)
  "TEXT, a unified diff, as files: (:file NAME :added N :removed N :hunks
HUNKS), each hunk (:header TEXT :lines ((KIND NUMBER TEXT)...)), KIND one of
context, added, removed, note; NUMBER the line's in the new file (for a
removed line, where it was: the old file's number is another file's, off
after a hunk that changed the count).

A hunk ends when its lines are used up (its @@ line's counts): then a ---
or +++ line is the next file's (`diff -u' outputs one after another, `diff
-ru'), \"-- \" a patch's signature (they were read as its lines, the next
file merged into it). Other lines past them (counts written wrong by hand)
are still its.

A combined diff's (diff --cc, during a merge: @@@ hunks), its lines with a
column of marks for each parent: added if one is +, removed if one is -
(they were read as nothing, an empty file)."
  (let (files file hunk old new (old-left 0) (new-left 0) (parents 1))
    (cl-flet* ((close-hunk () (when hunk
                                (setf (plist-get file :hunks)
                                      (append (plist-get file :hunks)
                                              (list (plist-put hunk :lines (nreverse (plist-get hunk :lines))))))
                                (setq hunk nil)))
               (close-file () (when file (push file files) (setq file nil)))
               (new-file () (close-hunk) (close-file)
                         (setq file (list :file "" :added 0 :removed 0 :hunks nil))))
      ;; Its end's newline isn't a line (in a diff, an empty line of context
      ;; is a space).
      (dolist (line (split-string (string-trim-right text "\n+") "\n"))
        ;; Past its counts: a line not of a hunk ends it.
        (when (and hunk (<= old-left 0) (<= new-left 0)
                   (not (string-prefix-p "\\" line))
                   (or (not (string-match-p "\\`[-+ ]" line))
                       (string-prefix-p "--- " line) (string-prefix-p "+++ " line) (equal line "-- ")))
          (close-hunk))
        (cond
         ((string-match "\\`diff --\\(?:cc\\|combined\\) \\(.*\\)\\'" line)
          (new-file)
          (let ((name (match-string 1 line)))
            (plist-put file :file (or (car (agent-ui-diff--unquote name)) name))))
         ((string-prefix-p "diff --git " line)
          (new-file)
          (plist-put file :file (agent-ui-diff--git-name (substring line (length "diff --git ")))))
         ;; A rename's (or copy's) new name: its own line (diff --git's
         ;; can't always be split).
         ((and file (not hunk) (string-match "\\`\\(?:rename\\|copy\\) to \\(.*\\)\\'" line))
          (let ((name (match-string 1 line)))
            (plist-put file :file (or (car (agent-ui-diff--unquote name)) name))))
         ((and (string-prefix-p "--- " line) (not hunk))
          ;; A file's, unless it's this one's (after diff --git).
          (when (or (null file) (plist-get file :hunks)) (new-file))
          (let ((name (string-remove-prefix "--- " line)))
            (when (and (equal (plist-get file :file) "") (not (equal name "/dev/null")))
              (plist-put file :file (agent-ui-diff--name name "a/")))))
         ((and (string-prefix-p "+++ " line) (not hunk))
          (when (or (null file) (plist-get file :hunks)) (new-file))
          (let ((name (string-remove-prefix "+++ " line)))
            (unless (equal name "/dev/null")
              (plist-put file :file (agent-ui-diff--name name "b/")))))
         ((string-match "\\`@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@\\(.*\\)\\'" line)
          (close-hunk)
          (unless file (new-file))
          (setq old (string-to-number (match-string 1 line))
                new (string-to-number (match-string 3 line))
                ;; No count: 1.
                old-left (if (match-string 2 line) (string-to-number (match-string 2 line)) 1)
                new-left (if (match-string 4 line) (string-to-number (match-string 4 line)) 1)
                parents 1
                hunk (list :header line :lines nil)))
         ;; A combined diff's: its result's counts (its parents' not kept).
         ((string-match "\\`\\(@@@+\\) \\(?:-[0-9]+\\(?:,[0-9]+\\)? \\)+\\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@@+" line)
          (close-hunk)
          (unless file (new-file))
          (setq parents (1- (length (match-string 1 line)))
                new (string-to-number (match-string 2 line))
                new-left (if (match-string 3 line) (string-to-number (match-string 3 line)) 1)
                old-left 0
                hunk (list :header line :lines nil)))
         ((not hunk))                   ; index, mode lines: not shown
         ((and (> parents 1) (not (string-prefix-p "\\" line)))
          (let ((marks (substring line 0 (min parents (length line))))
                (text (if (> (length line) parents) (substring line parents) "")))
            (cond ((string-search "+" marks)
                   (push (list 'added new text) (plist-get hunk :lines))
                   (cl-incf (plist-get file :added)) (cl-incf new) (cl-decf new-left))
                  ((string-search "-" marks)
                   (push (list 'removed new text) (plist-get hunk :lines))
                   (cl-incf (plist-get file :removed)))
                  ((not (and (string-empty-p line) (null (plist-get hunk :lines))))
                   (push (list 'context new text) (plist-get hunk :lines))
                   (cl-incf new) (cl-decf new-left)))))
         ((string-prefix-p "+" line)
          (push (list 'added new (substring line 1)) (plist-get hunk :lines))
          (cl-incf (plist-get file :added)) (cl-incf new) (cl-decf new-left))
         ((string-prefix-p "-" line)
          (push (list 'removed new (substring line 1)) (plist-get hunk :lines))
          (cl-incf (plist-get file :removed)) (cl-incf old) (cl-decf old-left))
         ((string-prefix-p "\\" line)
          ;; Its words without git's space after the \ (drawn after the
          ;; mark's own: two spaces).
          (push (list 'note nil (string-remove-prefix " " (substring line 1))) (plist-get hunk :lines)))
         ((or (string-prefix-p " " line) (string-empty-p line))
          (unless (and (string-empty-p line) (null (plist-get hunk :lines)))
            (push (list 'context new (if (string-empty-p line) "" (substring line 1))) (plist-get hunk :lines))
            (cl-incf old) (cl-incf new) (cl-decf old-left) (cl-decf new-left)))))
      (close-hunk) (close-file))
    (nreverse files)))

(defun agent-ui-diff--open (dir file line)
  "Open FILE (relative to DIR) at LINE."
  (lambda ()
    (funcall agent-ui-open-file-function (expand-file-name file dir))
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun agent-ui-diff--draw (props ctx gui)
  (let* ((files (agent-ui-diff--parse (plist-get props :diff)))
         (dir (plist-get props :dir))
         (width (plist-get ctx :width))
         (bg (or (face-background 'default nil t) "black"))
         (tint (lambda (face) (agent-ui-progress--blend bg (agent-ui-progress--color face) 0.18)))
         (count 0)
         (total (cl-loop for file in files
                         sum (cl-loop for hunk in (plist-get file :hunks) sum (length (plist-get hunk :lines)))))
         ;; Lines up to the cap, then nothing but what's left out said (later
         ;; files and hunks were drawn, empty, the note at the very end).
         (full (lambda () (and (>= count agent-ui-max-rows) (> total count))))
         ;; The line numbers' digits: the largest's, 5 at least (it was 5:
         ;; lines from 100000 a column past the width).
         (digits (max 5 (length (number-to-string
                                 (apply #'max 0 (cl-loop for file in files
                                                         append (cl-loop for hunk in (plist-get file :hunks)
                                                                         append (delq nil (mapcar #'cadr (plist-get hunk :lines))))))))))
         (out nil))
    (if (null files)
        (propertize "no changes" 'face 'agent-ui-muted)
      (catch 'full
        (dolist (file files)
          (when (funcall full) (throw 'full nil))
          (let* ((counts (concat "  " (propertize (format "+%d" (plist-get file :added)) 'face 'agent-ui-success)
                                 " " (propertize (format "−%d" (plist-get file :removed)) 'face 'agent-ui-error)))
                 ;; Its path cut at its start, its counts kept (it was never
                 ;; cut: the canvas cut it, the counts first).
                 (name (agent-ui-truncate-start (plist-get file :file)
                                                (max 1 (- width 2 (string-width counts))))))
            (push (agent-ui-truncate
                   (concat (propertize "▾ " 'face 'agent-ui-muted)
                           (agent-ui-button (propertize name 'face 'bold)
                                            (agent-ui-diff--open dir (plist-get file :file) nil)
                                            "RET: open the file")
                           counts)
                   width)
                  out))
          (dolist (hunk (plist-get file :hunks))
            (when (funcall full) (throw 'full nil))
            (push (concat "  " (propertize (agent-ui-truncate (plist-get hunk :header) (- width 2))
                                           'face 'agent-ui-accent))
                  out)
            (dolist (line (plist-get hunk :lines))
              (when (funcall full) (throw 'full nil))
              (cl-incf count)
              (pcase-let* ((`(,kind ,number ,text) line)
                           (mark (pcase kind ('added "+") ('removed "−") ('note "\\") (_ " ")))
                           (face (pcase kind ('added 'agent-ui-success) ('removed 'agent-ui-error)
                                        ('note 'agent-ui-muted) (_ nil)))
                           (gutter (if (and number (not (eq kind 'removed)))
                                       (format (format "%%%dd " digits) number)
                                     (make-string (1+ digits) ?\s)))
                           (body (agent-ui-truncate (concat mark " " (agent-ui-untabify text))
                                                    (- width 3 digits)))
                           (shown (concat "  " (propertize gutter 'face 'agent-ui-muted)
                                          (if face (propertize body 'face face) body))))
                (when (and gui (memq kind '(added removed)))
                  ;; A tint as wide as the pane, as code review tools have.
                  (setq shown (concat shown (make-string (max 0 (- width (string-width shown))) ?\s)))
                  (add-face-text-property 0 (length shown) (list :background (funcall tint face)) t shown))
                (push (agent-ui-button shown (agent-ui-diff--open dir (plist-get file :file) number)
                                       (format "RET: %s:%s" (plist-get file :file) (or number "")))
                      out))))))
      (when (> total count)
        (push (agent-ui-truncate (propertize (format "… %d lines more" (- total count)) 'face 'agent-ui-muted) width)
              out))
      (string-join (nreverse out) "\n"))))

(agent-ui-define diff
  "Changes, from a unified diff (git diff's): by file, its lines added and
removed counted, and hunk; added lines green, removed red; each line's
number in the new file. RET on a line opens its file there, relative to DIR
\(your directory). To follow the work tree: a source
{\"poll\": \"git diff\", \"every\": 5, \"into\": \"diff\"}."
  :props ((diff string "The unified diff (git diff's output)" :default "")
          (dir file "Where its files are (default: your directory)" :default :here))
  :example (:title "My changes"
            :diff "diff --git a/src/parser.c b/src/parser.c\n--- a/src/parser.c\n+++ b/src/parser.c\n@@ -40,3 +40,3 @@ parse_expr\n   int depth = 0;\n-  return NULL;\n+  return parse_term(p);\n }\n")
  :text (lambda (props ctx) (agent-ui-diff--draw props ctx nil))
  :gui (lambda (props ctx) (agent-ui-diff--draw props ctx t)))
