;;; $DOOMDIR/config/agent-ui/elements/code.el -*- lexical-binding: t; -*-
;; Agent UI's code: a snippet, highlighted, its lines linked to its file.
;; Loaded from config/agent-ui/elements.el.
;;
;; CODE (or, with no CODE, lines FROM to TO of FILE, read when drawn), in
;; LANGUAGE's mode (else FILE's), each line numbered from FROM; RET on a line
;; opens FILE there. MARKS: {"line", "kind", "note"}, kind error, warning,
;; change or info: its line marked in the gutter, its note after it. Unlike
;; Markdown's code blocks, clickable into the file.
;;
;;   40 │ int parse_expr(Parser *p) {
;;   41 ✗   return NULL;      ← never NULL here
;;   42 │ }

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-code--marks
  '((error "✗" agent-ui-error) (warning "!" agent-ui-warning) (change "+" agent-ui-success) (info "•" agent-ui-accent))
  "Each mark kind: its sign and face.")

(defun agent-ui-code--mode (language file)
  "The major mode for LANGUAGE (a mode's name without -mode: python, c,
emacs-lisp), else for FILE's name; nil if neither says."
  (or (and language
           (let ((mode (intern (concat (replace-regexp-in-string "-mode\\'" "" language) "-mode"))))
             (and (fboundp mode) mode)))
      (and file
           (let ((mode (assoc-default file auto-mode-alist #'string-match)))
             (and (symbolp mode) (fboundp mode) mode)))))

(defun agent-ui-code--highlight (code mode)
  "CODE highlighted by MODE (its faces as face properties); CODE if none."
  (if (not mode)
      code
    (with-temp-buffer
      (insert code)
      (delay-mode-hooks (ignore-errors (funcall mode)))
      (ignore-errors (font-lock-ensure))
      ;; font-lock-face as face: shown outside its buffer.
      (let ((pos (point-min)))
        (while (< pos (point-max))
          (let ((next (next-single-property-change pos 'font-lock-face nil (point-max)))
                (face (get-text-property pos 'font-lock-face)))
            (when face (put-text-property pos next 'face face))
            (setq pos next))))
      (buffer-string))))

(defun agent-ui-code--source (props)
  "The code: CODE, or FILE's lines FROM to TO; and what's wrong, said after
FILE's name (\": not found\"), or nil."
  (if-let* ((code (plist-get props :code)))
      ;; Its end's newlines aren't lines (a numbered empty one, widening the
      ;; gutter), nor CRLF's returns (^M).
      (cons (replace-regexp-in-string "\r$" "" (string-trim-right code "[\r\n]+")) nil)
    (let ((file (plist-get props :file)))
      (if (not (and file (file-readable-p file)))
          (cons "" ": not found")
        (with-temp-buffer
          (insert-file-contents file)
          (let* ((from (plist-get props :from))
                 (to (or (plist-get props :to) (+ from 19)))
                 (count (count-lines (point-min) (point-max))))
            (if (> from count)
                ;; Said (it was an empty line, numbered FROM).
                (cons "" (format ": lines %d–%d are past its end (%d line%s)" from to count (if (= count 1) "" "s")))
              (goto-char (point-min))
              (forward-line (1- from))
              (let ((start (point)))
                (forward-line (- to from -1))
                (cons (string-trim-right (buffer-substring start (point)) "\n") nil)))))))))

(defun agent-ui-code--check (props)
  (unless (or (plist-get props :code) (plist-get props :file))
    (agent-ui--fail "code: give code, or a file (and from, to)"))
  (when (< (plist-get props :from) 1)
    (agent-ui--fail "code: from is a line, 1 or more"))
  (when (and (plist-get props :to) (< (plist-get props :to) (plist-get props :from)))
    (agent-ui--fail "code: to is before from"))
  (plist-put props :marks
             (cl-loop for m in (plist-get props :marks)
                      for i from 1
                      collect (let ((kind (let ((k (plist-get m :kind))) (if (stringp k) (intern-soft k) (or k 'info)))))
                                (unless (and (agent-ui--plist-p m) (natnump (plist-get m :line)))
                                  (agent-ui--fail "code: mark %d must be {\"line\": N, \"kind\": ..., \"note\": ...}" i))
                                (unless (assq kind agent-ui-code--marks)
                                  (agent-ui--fail "code: mark %d's kind is error, warning, change or info" i))
                                (list :line (plist-get m :line) :kind kind :note (plist-get m :note))))))

(defun agent-ui-code--draw (props ctx)
  (pcase-let* ((`(,code . ,err) (agent-ui-code--source props))
               (file (plist-get props :file))
               (from (plist-get props :from))
               (width (plist-get ctx :width))
               (lines (split-string (agent-ui-code--highlight code (agent-ui-code--mode (plist-get props :language) file)) "\n"))
               (last-number (+ from (length lines) -1))
               (gutter (length (number-to-string last-number))))
    (if err
        ;; Its file's name cut at its start (never cut: 72 columns at 15).
        (propertize (concat (agent-ui-truncate-start (abbreviate-file-name file)
                                                     (max 1 (- width (string-width err))))
                            err)
                    'face 'agent-ui-muted)
      (concat
       (when file
         (concat (propertize (agent-ui-truncate-start (abbreviate-file-name file) width) 'face 'agent-ui-muted)
                 "\n"))
       (string-join
        (cl-loop for line in (seq-take lines agent-ui-max-rows)
                 for n from from
                 collect (let* (;; Its marks, the worst first: its sign; every note (it
                                ;; showed the first mark only).
                                (marks (cl-stable-sort
                                        (cl-remove-if-not (lambda (m) (eql (plist-get m :line) n)) (plist-get props :marks))
                                        #'< :key (lambda (m) (cl-position (plist-get m :kind) agent-ui-code--marks :key #'car))))
                                (kind (and marks (assq (plist-get (car marks) :kind) agent-ui-code--marks)))
                                (text (string-replace "\t" "    " line))
                                (body (agent-ui-truncate text (- width gutter 3)))
                                (notes (cl-loop for m in marks
                                                when (plist-get m :note)
                                                collect (propertize (plist-get m :note) 'face
                                                                    (nth 2 (assq (plist-get m :kind) agent-ui-code--marks)))))
                                (note (and notes (concat (propertize "← " 'face (nth 2 kind))
                                                         (string-join notes (propertize "; " 'face 'agent-ui-muted)))))
                                (head (concat (propertize (format (format "%%%dd" gutter) n) 'face 'agent-ui-muted) " "
                                              (if kind (propertize (nth 1 kind) 'face (nth 2 kind))
                                                (propertize "│" 'face 'agent-ui-muted))
                                              " "))
                                (shown
                                 (cond
                                  ((not note) (concat head body))
                                  ;; Its note after it, if both fit.
                                  ((<= (+ gutter 3 (string-width text) 2 (string-width note)) width)
                                   (concat head text "  " note))
                                  ;; Else under it, wrapped (cut with the line, it went).
                                  (t (concat head body
                                             (mapconcat (lambda (part)
                                                          (concat "\n" (make-string (+ gutter 3) ?\s) part))
                                                        (split-string (agent-ui-wrap note (max 1 (- width gutter 3))) "\n")
                                                        ""))))))
                           (if file
                               (agent-ui-button shown
                                                (let ((n n))
                                                  (lambda ()
                                                    (funcall agent-ui-open-file-function file)
                                                    (goto-char (point-min))
                                                    (forward-line (1- n))))
                                                (format "RET: %s:%d" (abbreviate-file-name file) n))
                             shown)))
        "\n")))))

(agent-ui-define code
  "A code snippet, highlighted by its LANGUAGE's mode (python, c, rust,
emacs-lisp...; else FILE's), each line numbered from FROM and linked to
FILE (RET opens it there). CODE, or FILE's lines FROM to TO read as they
are now. MARKS: {\"line\", \"kind\", \"note\"}, kind error, warning, change
or info, a sign in the gutter and the note after the line. For the line
an error is on, the code a change is about."
  :props ((code string "The code (default: FILE's lines FROM to TO)")
          (file file "Its file: lines link there; read if no CODE")
          (from integer "Its first line's number" :default 1)
          (to integer "With FILE and no CODE: its last line (default FROM + 19)")
          (language string "Its language: a mode's name without -mode")
          (marks list "Marked lines: {\"line\", \"kind\", \"note\"}"))
  :example (:title "Where it fails" :language "c" :from 40
            :code "int parse_expr(Parser *p) {\n  return NULL;\n}"
            :marks ((:line 41 :kind "error" :note "never NULL here")))
  :check #'agent-ui-code--check
  :text #'agent-ui-code--draw)
