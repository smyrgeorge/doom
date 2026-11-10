;;; $DOOMDIR/config/agent-ui/elements/files.el -*- lexical-binding: t; -*-
;; Agent UI's files: files, each with its state and counts, flat or as a tree
;; by folder. Loaded from config/agent-ui/elements.el.
;;
;; A file is a path, or {"path", "status", "added", "removed", "errors",
;; "line", "note"}: status changed, added, deleted, renamed, failing, passing
;; or none, coloured; counts after it. RET on a file opens it (at its line),
;; relative to DIR (the agent's directory); in a tree, RET on a folder folds
;; it (in a canvas). For what the agent touched, or where the errors are.
;;
;;   ▾ src/
;;       M parser.c      +12 −3
;;       A lexer.h        +40
;;   ▾ tests/
;;       ✗ parser_test.c  2 errors

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-files--statuses
  '((changed "M" agent-ui-warning) (added "A" agent-ui-success) (deleted "D" agent-ui-error)
    (renamed "R" agent-ui-accent) (failing "✗" agent-ui-error) (passing "✓" agent-ui-success)
    (none " " agent-ui-muted))
  "Each status: its mark and face.")

(defun agent-ui-files--normal (path)
  "PATH written one way: without ./ parts nor doubled slashes (./src//a.c is
src/a.c; a tree grouped them in folders of their own)."
  (let ((p (replace-regexp-in-string "/\\{2,\\}" "/" path)))
    (while (string-match "\\(?:\\`\\|/\\)\\(\\./\\)" p)
      (setq p (replace-match "" t t p 1)))
    (if (string-empty-p p) path p)))

(defun agent-ui-files--file (entry index)
  "ENTRY (a path, or an object) as (:path :status :added :removed :errors
:line :note); an error naming file INDEX if it's wrong."
  (cl-flet ((bad (what) (agent-ui--fail "files: file %d%s%s" index (if (string-prefix-p "'" what) "" " ") what)))
    (cond
     ((and (stringp entry) (not (string-blank-p entry)))
      (list :path (agent-ui-files--normal entry) :status 'none))
     ((agent-ui--plist-p entry)
      (cl-loop for (k _) on entry by #'cddr
               unless (memq k '(:path :status :added :removed :errors :line :note))
               do (bad (format "has %s: a file has path, status, added, removed, errors, line, note"
                               (agent-ui--show-value (substring (symbol-name k) 1)))))
      (unless (stringp (plist-get entry :path)) (bad "has no path"))
      (let ((status (let ((s (plist-get entry :status))) (if (stringp s) (intern-soft s) (or s 'none)))))
        (unless (assq status agent-ui-files--statuses)
          (bad (format "has status %s; one of: changed, added, deleted, renamed, failing, passing, none"
                       (agent-ui--show-value (plist-get entry :status)))))
        (dolist (k '(:added :removed :errors :line))
          (when (and (plist-get entry k) (not (natnump (plist-get entry k))))
            (bad (format "'s %s must be a count" (substring (symbol-name k) 1)))))
        ;; Else accepted, then drawing it failed.
        (when (and (plist-get entry :note) (not (stringp (plist-get entry :note))))
          (bad "'s note must be text"))
        (plist-put (plist-put (copy-sequence entry) :status status)
                   :path (agent-ui-files--normal (plist-get entry :path)))))
     (t (bad (format "is %s: a path, or {\"path\": ..., \"status\": ...}" (agent-ui--show-value entry)))))))

(defun agent-ui-files--check (props)
  (plist-put props :files (cl-loop for f in (plist-get props :files)
                                   for i from 1
                                   collect (agent-ui-files--file f i))))

(defun agent-ui-files--counts (file)
  "FILE's counts, coloured, then its note: (\"+12\" \"−3\" \"2 errors\")."
  (delq nil (list (and (plist-get file :added) (propertize (format "+%d" (plist-get file :added)) 'face 'agent-ui-success))
                  (and (plist-get file :removed) (propertize (format "−%d" (plist-get file :removed)) 'face 'agent-ui-error))
                  (and (plist-get file :errors)
                       (propertize (format "%d error%s" (plist-get file :errors) (if (= (plist-get file :errors) 1) "" "s"))
                                   'face 'agent-ui-error))
                  (and (plist-get file :note) (propertize (plist-get file :note) 'face 'agent-ui-muted)))))

(defun agent-ui-files--fit (file items room)
  "FILE's counts ITEMS, in ROOM columns: whole counts while they fit (a cut
one misreads: \"+12…\" for +1200), its note cut (4 columns at least)."
  (let ((out "") (note (plist-get file :note)))
    (catch 'full
      (dolist (item items)
        (let* ((sep (if (string-empty-p out) "" " "))
               (left (- room (string-width out) (length sep))))
          (cond ((<= (string-width item) left) (setq out (concat out sep item)))
                ((and note (eq item (car (last items))) (>= left 4))
                 (setq out (concat out sep (agent-ui-truncate item left)))
                 (throw 'full nil))
                (t (throw 'full nil))))))
    out))

(defun agent-ui-files--open (dir file)
  (lambda ()
    (funcall agent-ui-open-file-function (expand-file-name (plist-get file :path) dir))
    (when-let* ((line (plist-get file :line)))
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun agent-ui-files--line (props file name items indent name-width room)
  "FILE's line: INDENT, its mark, NAME in NAME-WIDTH columns, its counts
ITEMS, those that fit; ROOM the columns after the mark (the name's all, if
no count fits)."
  (pcase-let* ((`(,_ ,mark ,face) (assq (plist-get file :status) agent-ui-files--statuses))
               (counts (agent-ui-files--fit file items (- room name-width 2))))
    (agent-ui-button
     (concat indent (propertize mark 'face face) " "
             (if (string-empty-p counts)
                 (agent-ui-truncate-start name room)
               (concat (agent-ui-pad (agent-ui-truncate-start name name-width) name-width) "  " counts)))
     (agent-ui-files--open (plist-get props :dir) file)
     (format "RET: open %s" (plist-get file :path)))))

(defun agent-ui-files--lines (props files names indent width)
  "FILES' lines, NAMES their names, after INDENT, WIDTH columns at most: the
names beside counts in a column as wide as the longest, narrowed while the
counts don't fit (8 columns at least; it was the width less 20, or 24:
nothing under that, and the counts never cut)."
  (let* ((room (- width (string-width indent) 2))
         (counts (mapcar #'agent-ui-files--counts files))
         (longest (apply #'max 0 (cl-loop for n in names for c in counts
                                           when c collect (string-width n))))
         (widest (apply #'max 0 (mapcar (lambda (c) (string-width (string-join c " "))) counts)))
         (w (min longest (max (min longest 8) (- room 2 widest)))))
    (cl-mapcar (lambda (file name count) (agent-ui-files--line props file name count indent w room))
               files names counts)))

(defun agent-ui-files--toggle (ctx folder folded)
  (lambda ()
    (let ((id (plist-get ctx :id)))
      (unless (and id (derived-mode-p 'agent-ui-canvas-mode))
        (user-error "Folders fold in a canvas"))
      (agent-ui-update id (list :folded (if (member folder folded) (remove folder folded)
                                          (append folded (list folder))))
                       :canvas (current-buffer)))))

(defun agent-ui-files--draw (props ctx)
  (let* ((files (seq-take (plist-get props :files) agent-ui-max-rows))
         (more (- (length (plist-get props :files)) (length files)))
         (width (plist-get ctx :width))
         (lines
          (if (not (plist-get props :tree))
              (agent-ui-files--lines props files (mapcar (lambda (f) (plist-get f :path)) files) "" width)
            ;; A tree: files grouped by folder, in their order of first coming.
            ;; A path ending in / is a folder: its mark and counts on its line
            ;; (it was a file without a name, a blank row).
            (let ((folders nil) (own nil) (folded (plist-get props :folded)))
              (dolist (f files)
                (let* ((path (plist-get f :path))
                       (folder (if (string-suffix-p "/" path) path (or (file-name-directory path) ""))))
                  (unless (assoc folder folders) (push (list folder) folders))
                  (if (string-suffix-p "/" path)
                      (push (cons folder f) own)
                    (setf (alist-get folder folders nil nil #'equal)
                          (append (alist-get folder folders nil nil #'equal) (list f))))))
              (apply #'append
                     (mapcar
                      (lambda (entry)
                        (let* ((folder (car entry))
                               (closed (member folder folded))
                               (names (mapcar (lambda (f) (file-name-nondirectory (plist-get f :path))) (cdr entry))))
                          (if (equal folder "")
                              (agent-ui-files--lines props (cdr entry) names "" width)
                            (let* ((count (if closed (format "  %d files" (length names)) ""))
                                   (self (cdr (assoc folder own)))
                                   (status (and self (assq (plist-get self :status) agent-ui-files--statuses)))
                                   (mark (if (and status (not (eq (car status) 'none)))
                                             (concat (propertize (nth 1 status) 'face (nth 2 status)) " ")
                                           ""))
                                   (counts (if self (string-join (agent-ui-files--counts self) " ") ""))
                                   (counts (if (string-empty-p counts) "" (concat "  " counts))))
                              (cons (agent-ui-truncate
                                     (agent-ui-button
                                      (concat (propertize (if closed "▸ " "▾ ") 'face 'agent-ui-muted)
                                              mark
                                              ;; Cut at its start, as a file's name.
                                              (propertize (agent-ui-truncate-start
                                                           folder (max (min (string-width folder) 8)
                                                                       (- width 2 (string-width mark) (string-width counts)
                                                                          (string-width count))))
                                                          'face 'bold)
                                              counts
                                              (propertize count 'face 'agent-ui-muted))
                                      (agent-ui-files--toggle ctx folder folded)
                                      "RET: fold or unfold it")
                                     width)
                                    (unless closed
                                      (agent-ui-files--lines props (cdr entry) names "    " width)))))))
                      (nreverse folders)))))))
    (cond
     ((null files) (propertize "no files" 'face 'agent-ui-muted))
     (t (concat (string-join lines "\n")
                (if (> more 0)
                    (concat "\n" (agent-ui-truncate (propertize (format "… %d files more" more) 'face 'agent-ui-muted)
                                                    width))
                  ""))))))

(agent-ui-define files
  "Files, each with its state: a path, or {\"path\", \"status\", \"added\",
\"removed\", \"errors\", \"line\", \"note\"}; status changed, added,
deleted, renamed, failing, passing or none (coloured marks), counts after
it. TREE groups them by folder (RET on a folder folds it). RET on a file
opens it, at its line. For what you touched, or where the errors are."
  :props ((files list "The files: paths, or {\"path\": ..., \"status\": ..., ...}")
          (tree boolean "Group them by folder, a tree" :default :false)
          (folded list "The folders folded (the user's)")
          (dir file "Where they are (default: your directory)" :default :here))
  :example (:title "What I changed" :tree t
            :files ((:path "src/parser.c" :status "changed" :added 12 :removed 3)
                    (:path "src/lexer.h" :status "added" :added 40)
                    (:path "tests/parser_test.c" :status "failing" :errors 2 :line 88)))
  :check #'agent-ui-files--check
  :text #'agent-ui-files--draw)
