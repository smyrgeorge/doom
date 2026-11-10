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

;; ====== ACCEPTING HUNKS ======
;; With accept: the user accepts or rejects each hunk of a diff the agent
;; proposes. Each is accepted to begin with; x on any of its lines (or RET on
;; its mark) rejects it, again: back; Accept all / Reject all. Send puts
;; "Answer to diff ID (QUESTION): accepted: FILE @@ ... @@; ...; rejected:
;; ..." into the session's prompt (at once unless accept's submit is false),
;; with the review comments if there are; then it's answered. Applying them
;; stays the agent's. Which are rejected is the element's own (:rejected,
;; ({file, hunk}...), hunk counted from 1 in its file), saved with it.

(defconst agent-ui-diff--question "Apply these changes?")

(defun agent-ui-diff--accept-props (props)
  "PROPS' accept as (:question :submit), or nil if it has none."
  (let ((accept (plist-get props :accept)))
    (cond ((memq accept '(nil :false)) nil)
          ((eq accept t) (list :question agent-ui-diff--question :submit t))
          (t (list :question (or (plist-get accept :question) agent-ui-diff--question)
                   :submit (not (eq (plist-get accept :submit) :false)))))))

(defun agent-ui-diff--check (props)
  (agent-ui-review-check "diff" (plist-get props :comments))
  (let ((accept (plist-get props :accept)))
    (unless (or (memq accept '(nil t :false))
                (and (agent-ui--plist-p accept)
                     (cl-every (lambda (k) (memq k '(:question :submit)))
                               (cl-loop for (k _) on accept by #'cddr collect k))
                     (or (null (plist-get accept :question)) (stringp (plist-get accept :question)))
                     (memq (plist-get accept :submit) '(nil t :false))))
      (agent-ui--fail "diff: accept is true, or {\"question\": ..., \"submit\": ...}")))
  (unless (cl-every (lambda (r) (and (agent-ui--plist-p r) (stringp (plist-get r :file))
                                     (natnump (plist-get r :hunk))))
                    (plist-get props :rejected))
    (agent-ui--fail "diff: rejected is [{\"file\": ..., \"hunk\": N}]: a file's hunks counted from 1"))
  props)

(defun agent-ui-diff--rejected-p (props file n)
  "Whether FILE's hunk N is rejected in PROPS."
  (seq-find (lambda (r) (and (equal (plist-get r :file) file) (eql (plist-get r :hunk) n)))
            (plist-get props :rejected)))

(defun agent-ui-diff--toggle (props ctx file n)
  "FILE's hunk N rejected, or accepted again."
  (let ((rejected (plist-get props :rejected)))
    (agent-ui-ask-change
     ctx (list :rejected (if (agent-ui-diff--rejected-p props file n)
                             (seq-remove (lambda (r) (and (equal (plist-get r :file) file) (eql (plist-get r :hunk) n)))
                                         rejected)
                           (append rejected (list (list :file file :hunk n))))))))

(defun agent-ui-diff--hunks (files)
  "FILES' hunks: ((FILE N HUNK)...), N counted from 1 in FILE."
  (cl-loop for file in files
           append (cl-loop for hunk in (plist-get file :hunks)
                           for n from 1
                           collect (list (plist-get file :file) n hunk))))

(defun agent-ui-diff--decided (props files)
  "FILES' hunks as PROPS has them: (ACCEPTED . REJECTED), each a list of
\"FILE @@ ... @@\"."
  (let (accepted rejected)
    (pcase-dolist (`(,file ,n ,hunk) (agent-ui-diff--hunks files))
      (let ((name (concat file " " (plist-get hunk :header))))
        (if (agent-ui-diff--rejected-p props file n) (push name rejected) (push name accepted))))
    (cons (nreverse accepted) (nreverse rejected))))

(defun agent-ui-diff--counted (accepted rejected comments)
  "\"2 accepted, 1 rejected, 1 comment\"."
  (string-join (delq nil (list (format "%d accepted" (length accepted))
                               (format "%d rejected" (length rejected))
                               (and comments (format "%d comment%s" (length comments)
                                                     (if (cdr comments) "s" "")))))
               ", "))

(defun agent-ui-diff--send (props ctx files)
  "The hunks accepted and rejected (and the comments) into the session's
prompt; answered."
  (pcase-let* ((accept (agent-ui-diff--accept-props props))
               (`(,accepted . ,rejected) (agent-ui-diff--decided props files))
               (comments (plist-get props :comments)))
    (funcall agent-ui-action-function
             (concat (format "Answer to diff %s (%s): " (plist-get ctx :id) (plist-get accept :question))
                     (string-join (delq nil (list (and accepted (concat "accepted: " (string-join accepted "; ")))
                                                  (and rejected (concat "rejected: " (string-join rejected "; ")))))
                                  ". ")
                     (if comments
                         (concat ". " (agent-ui-review-text (plist-get ctx :id) comments))
                       ""))
             (plist-get accept :submit))
    (agent-ui-ask-change ctx (list :answered (agent-ui-diff--counted accepted rejected comments)))))

(defun agent-ui-diff--accept-footer (props ctx files)
  "Under a diff with accept: the hint, Send, Accept all, Reject all; once
sent, saying so. Led by a newline."
  (pcase-let ((`(,accepted . ,rejected) (agent-ui-diff--decided props files))
              (width (plist-get ctx :width)))
    (cond
     ((agent-ui-ask-answered-p props)
      (concat "\n" (propertize "✓ " 'face 'agent-ui-success)
              (propertize (format "Sent: %s" (plist-get props :answered)) 'face 'agent-ui-muted)))
     ((plist-get ctx :still) "")
     (t
      (concat "\n"
              (propertize (agent-ui-wrap "x on a hunk rejects it (again: back), c comments on a line" width)
                          'face 'agent-ui-muted)
              "\n"
              (agent-ui-button (propertize (format "⏵ Send (%s)" (agent-ui-diff--counted accepted rejected
                                                                                          (plist-get props :comments)))
                                           'face 'agent-ui-action)
                               (lambda () (agent-ui-diff--send props ctx files))
                               "RET: tell the agent which hunks to apply")
              "   "
              (agent-ui-button (propertize "⏵ Accept all" 'face 'agent-ui-action)
                               (lambda () (agent-ui-ask-change ctx (list :rejected nil)))
                               "RET: accept every hunk")
              "   "
              (agent-ui-button (propertize "⏵ Reject all" 'face 'agent-ui-action)
                               (lambda ()
                                 (agent-ui-ask-change
                                  ctx (list :rejected (mapcar (lambda (h) (list :file (car h) :hunk (cadr h)))
                                                              (agent-ui-diff--hunks files)))))
                               "RET: reject every hunk"))))))

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
         (accept (and (agent-ui-diff--accept-props props) t))
         ;; Its hunks to accept or reject here: not answered, not a picture.
         (deciding (and accept (not (agent-ui-ask-answered-p props)) (not (plist-get ctx :still))))
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
          (cl-loop
           for hunk in (plist-get file :hunks)
           for n from 1
           do
           ;; Its own (the loop's are one variable each, set again).
           (let* ((hunk hunk)
                  (name (plist-get file :file))
                  (rejected (and accept (agent-ui-diff--rejected-p props name n)))
                  (toggle (let ((n n)) (lambda () (agent-ui-diff--toggle props ctx name n)))))
            (when (funcall full) (throw 'full nil))
            (push (if (not accept)
                      (concat "  " (propertize (agent-ui-truncate (plist-get hunk :header) (- width 2))
                                               'face 'agent-ui-accent))
                    (let ((mark (if rejected (propertize "✗" 'face 'agent-ui-error) (propertize "✓" 'face 'agent-ui-success)))
                          (header (propertize (agent-ui-truncate (plist-get hunk :header) (- width 4))
                                              'face (if rejected 'agent-ui-muted 'agent-ui-accent))))
                      (if deciding
                          (propertize (concat "  " (agent-ui-button mark toggle (if rejected "RET or x: accept it again"
                                                                                  "RET or x: reject it"))
                                              " " header)
                                      'agent-ui-drop toggle)
                        (concat "  " mark " " header))))
                  out)
            (cl-loop
             for (line . rest) on (plist-get hunk :lines)
             do
              (when (funcall full) (throw 'full nil))
              (cl-incf count)
              (pcase-let* ((`(,kind ,number ,text) line)
                           (mark (pcase kind ('added "+") ('removed "−") ('note "\\") (_ " ")))
                           ;; A rejected hunk's lines dimmed.
                           (face (if rejected
                                     'agent-ui-muted
                                   (pcase kind ('added 'agent-ui-success) ('removed 'agent-ui-error)
                                          ('note 'agent-ui-muted) (_ nil))))
                           (gutter (if (and number (not (eq kind 'removed)))
                                       (format (format "%%%dd " digits) number)
                                     (make-string (1+ digits) ?\s)))
                           (body (agent-ui-truncate (concat mark " " (agent-ui-untabify text))
                                                    (- width 3 digits)))
                           (shown (concat "  " (propertize gutter 'face 'agent-ui-muted)
                                          (if face (propertize body 'face face) body))))
                (when (and gui (memq kind '(added removed)) (not rejected))
                  ;; A tint as wide as the pane, as code review tools have.
                  (setq shown (concat shown (make-string (max 0 (- width (string-width shown))) ?\s)))
                  (add-face-text-property 0 (length shown) (list :background (funcall tint face)) t shown))
                ;; Where it is (c comments on it).
                (push (apply #'propertize (agent-ui-button shown (agent-ui-diff--open dir (plist-get file :file) number)
                                                           (format "RET: %s:%s" (plist-get file :file) (or number "")))
                             'agent-ui-line number 'agent-ui-file (plist-get file :file)
                             ;; x rejects its hunk (again: back).
                             (and deciding (list 'agent-ui-drop toggle)))
                      out)
                ;; Its comments under the last line of its number (a removed
                ;; line has the next one's).
                (when (and number (not (eql (cadr (car rest)) number)))
                  (let ((comments (agent-ui-review-lines props (plist-get file :file) number
                                                         (make-string (+ 3 digits) ?\s) width)))
                    (unless (string-empty-p comments)
                      (push (substring comments 1) out))))))))))
      (when (> total count)
        (push (agent-ui-truncate (propertize (format "… %d lines more" (- total count)) 'face 'agent-ui-muted) width)
              out))
      (concat (string-join (nreverse out) "\n")
              (if accept
                  (agent-ui-diff--accept-footer props ctx files)
                (agent-ui-review-footer props ctx))))))

(agent-ui-define diff
  "Changes, from a unified diff (git diff's): by file, its lines added and
removed counted, and hunk; added lines green, removed red; each line's
number in the new file. RET on a line opens its file there, relative to DIR
\(your directory). To follow the work tree: a source
{\"poll\": \"git diff\", \"every\": 5, \"into\": \"diff\"}. With ACCEPT, changes you
propose: the user accepts or rejects each hunk, and \"Answer to diff ID
\(QUESTION): accepted: FILE @@ ... @@; ...; rejected: ...\" comes into your
prompt; apply the accepted ones."
  :props ((diff string "The unified diff (git diff's output)" :default "")
          (dir file "Where its files are (default: your directory)" :default :here)
          (comments list "The user's review comments on its lines (c on a line): [{\"line\", \"end\", \"file\", \"text\"}]")
          (accept any "Changes you propose, the user accepting or rejecting each hunk: true, or {\"question\": ..., \"submit\": ...}")
          (rejected list "The hunks the user rejected: [{\"file\", \"hunk\": N}] (theirs)")
          (answered string "The review sent (then it can't be changed)"))
  :example (:title "My changes"
            :diff "diff --git a/src/parser.c b/src/parser.c\n--- a/src/parser.c\n+++ b/src/parser.c\n@@ -40,3 +40,3 @@ parse_expr\n   int depth = 0;\n-  return NULL;\n+  return parse_term(p);\n }\n")
  :check #'agent-ui-diff--check
  :text (lambda (props ctx) (agent-ui-diff--draw props ctx nil))
  :gui (lambda (props ctx) (agent-ui-diff--draw props ctx t)))
