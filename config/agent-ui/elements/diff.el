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

(defun agent-ui-diff--parse (text)
  "TEXT, a unified diff, as files: (:file NAME :added N :removed N :hunks
HUNKS), each hunk (:header TEXT :lines ((KIND NUMBER TEXT)...)), KIND one of
context, added, removed, note; NUMBER the line's in the new file (for a
removed line, where it was: the old file's number is another file's, off
after a hunk that changed the count)."
  (let (files file hunk old new)
    (cl-flet ((close-hunk () (when hunk
                               (setf (plist-get file :hunks)
                                     (append (plist-get file :hunks)
                                             (list (plist-put hunk :lines (nreverse (plist-get hunk :lines))))))
                               (setq hunk nil)))
              (close-file () (when file (push file files) (setq file nil))))
      ;; Its end's newline isn't a line (in a diff, an empty line of context
      ;; is a space).
      (dolist (line (split-string (string-trim-right text "\n+") "\n"))
        (cond
         ((string-prefix-p "diff --git " line)
          (close-hunk) (close-file)
          (setq file (list :file (if (string-match " b/\\(.*\\)\\'" line) (match-string 1 line) "")
                           :added 0 :removed 0 :hunks nil)))
         ((and (string-prefix-p "+++ " line) (not hunk))
          (unless file (setq file (list :file "" :added 0 :removed 0 :hunks nil)))
          (let ((name (string-remove-prefix "+++ " line)))
            (unless (equal name "/dev/null")
              (plist-put file :file (replace-regexp-in-string "\\`b/" "" (car (split-string name "\t")))))))
         ((and (string-prefix-p "--- " line) (not hunk))
          (unless file (setq file (list :file "" :added 0 :removed 0 :hunks nil)))
          (let ((name (string-remove-prefix "--- " line)))
            (when (and (equal (plist-get file :file) "") (not (equal name "/dev/null")))
              (plist-put file :file (replace-regexp-in-string "\\`a/" "" (car (split-string name "\t")))))))
         ((string-match "\\`@@ -\\([0-9]+\\)\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,[0-9]+\\)? @@\\(.*\\)\\'" line)
          (close-hunk)
          (unless file (setq file (list :file "" :added 0 :removed 0 :hunks nil)))
          (setq old (string-to-number (match-string 1 line))
                new (string-to-number (match-string 2 line))
                hunk (list :header line :lines nil)))
         ((not hunk))                   ; index, mode lines: not shown
         ((string-prefix-p "+" line)
          (push (list 'added new (substring line 1)) (plist-get hunk :lines))
          (cl-incf (plist-get file :added)) (cl-incf new))
         ((string-prefix-p "-" line)
          (push (list 'removed new (substring line 1)) (plist-get hunk :lines))
          (cl-incf (plist-get file :removed)) (cl-incf old))
         ((string-prefix-p "\\" line)
          (push (list 'note nil (substring line 1)) (plist-get hunk :lines)))
         ((or (string-prefix-p " " line) (string-empty-p line))
          (unless (and (string-empty-p line) (null (plist-get hunk :lines)))
            (push (list 'context new (if (string-empty-p line) "" (substring line 1))) (plist-get hunk :lines))
            (cl-incf old) (cl-incf new)))))
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
         (out nil))
    (if (null files)
        (propertize "no changes" 'face 'agent-ui-muted)
      (dolist (file files)
        (push (concat (propertize "▾ " 'face 'agent-ui-muted)
                      (agent-ui-button (propertize (plist-get file :file) 'face 'bold)
                                       (agent-ui-diff--open dir (plist-get file :file) nil)
                                       "RET: open the file")
                      "  "
                      (propertize (format "+%d" (plist-get file :added)) 'face 'agent-ui-success)
                      " "
                      (propertize (format "−%d" (plist-get file :removed)) 'face 'agent-ui-error))
              out)
        (dolist (hunk (plist-get file :hunks))
          (push (concat "  " (propertize (agent-ui-truncate (plist-get hunk :header) (- width 2))
                                         'face 'agent-ui-accent))
                out)
          (dolist (line (plist-get hunk :lines))
            (cl-incf count)
            (when (<= count agent-ui-max-rows)
              (pcase-let* ((`(,kind ,number ,text) line)
                           (mark (pcase kind ('added "+") ('removed "−") ('note "\\") (_ " ")))
                           (face (pcase kind ('added 'agent-ui-success) ('removed 'agent-ui-error)
                                        ('note 'agent-ui-muted) (_ nil)))
                           (gutter (if (and number (not (eq kind 'removed))) (format "%5d " number) "      "))
                           (body (agent-ui-truncate (concat mark " " (string-replace "\t" "    " text))
                                                    (- width 8)))
                           (shown (concat "  " (propertize gutter 'face 'agent-ui-muted)
                                          (if face (propertize body 'face face) body))))
                (when (and gui (memq kind '(added removed)))
                  ;; A tint as wide as the pane, as code review tools have.
                  (setq shown (concat shown (make-string (max 0 (- width (string-width shown))) ?\s)))
                  (add-face-text-property 0 (length shown) (list :background (funcall tint face)) t shown))
                (push (agent-ui-button shown (agent-ui-diff--open dir (plist-get file :file) number)
                                       (format "RET: %s:%s" (plist-get file :file) (or number "")))
                      out))))))
      (when (> count agent-ui-max-rows)
        (push (propertize (format "… %d lines more" (- count agent-ui-max-rows)) 'face 'agent-ui-muted) out))
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
